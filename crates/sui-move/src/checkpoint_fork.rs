// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

use anyhow::{Context, Result};
use sui_json_rpc_types::{CheckpointId, SuiObjectDataOptions, SuiTransactionBlockEffectsAPI};
use sui_protocol_config::ProtocolConfig;
use sui_sdk::SuiClientBuilder;
use sui_types::{
    base_types::ObjectID, in_memory_storage::InMemoryStorage,
    messages_checkpoint::CheckpointSequenceNumber, object::Object,
};
use tracing::{info, warn};

const BATCH_SIZE: usize = 50;
// Maximum number of checkpoints to scan backwards from target
// Scanning from 0 to large checkpoint numbers (millions) is impractical
const MAX_CHECKPOINT_SCAN_RANGE: u64 = 1000;

pub struct CheckpointStateLoader {
    rpc_url: String,
}

impl CheckpointStateLoader {
    pub fn new(rpc_url: String) -> Self {
        Self { rpc_url }
    }

    /// Load all objects from a checkpoint into InMemoryStorage
    pub async fn load_checkpoint_state(
        &self,
        checkpoint_seq: CheckpointSequenceNumber,
    ) -> Result<InMemoryStorage> {
        info!(
            "Loading checkpoint state from checkpoint {} at {}",
            checkpoint_seq, self.rpc_url
        );

        let client = SuiClientBuilder::default()
            .build(&self.rpc_url)
            .await
            .context("Failed to create Sui client")?;

        let checkpoint = client
            .read_api()
            .get_checkpoint(CheckpointId::SequenceNumber(checkpoint_seq.into()))
            .await
            .context("Failed to fetch checkpoint")?;

        info!(
            "Checkpoint {} found at epoch {} with {} transactions",
            checkpoint_seq, checkpoint.epoch, checkpoint.network_total_transactions
        );

        let object_states = self
            .fetch_objects_from_contents(&client, checkpoint_seq)
            .await?;

        info!(
            "Successfully loaded {} objects from checkpoint {}",
            object_states.len(),
            checkpoint_seq
        );

        Ok(InMemoryStorage::new(object_states))
    }

    async fn fetch_objects_from_contents(
        &self,
        client: &sui_sdk::SuiClient,
        checkpoint_seq: CheckpointSequenceNumber,
    ) -> Result<Vec<Object>> {
        // Calculate scan range: either from 0 or from (target - MAX_CHECKPOINT_SCAN_RANGE)
        let start_seq = checkpoint_seq.saturating_sub(MAX_CHECKPOINT_SCAN_RANGE);
        let scan_range = checkpoint_seq - start_seq + 1;

        info!(
            "Fetching objects modified in checkpoint range {} to {} ({} checkpoints)",
            start_seq, checkpoint_seq, scan_range
        );

        if start_seq > 0 {
            warn!(
                "Note: Only scanning last {} checkpoints. Objects from earlier checkpoints will not be available.",
                MAX_CHECKPOINT_SCAN_RANGE
            );
        }

        let mut all_object_ids = std::collections::HashSet::new();
        let mut current_seq = start_seq;

        while current_seq <= checkpoint_seq {
            let checkpoint = match client
                .read_api()
                .get_checkpoint(CheckpointId::SequenceNumber(current_seq.into()))
                .await
            {
                Ok(cp) => cp,
                Err(e) => {
                    warn!("Failed to fetch checkpoint {}: {}", current_seq, e);
                    current_seq += 1;
                    continue;
                }
            };

            let tx_count = checkpoint.transactions.len();
            if tx_count > 0 {
                info!(
                    "Processing checkpoint {} with {} transactions",
                    current_seq, tx_count
                );
            }

            for tx_digest in checkpoint.transactions {
                if let Ok(tx_response) = client
                    .read_api()
                    .get_transaction_with_options(
                        tx_digest,
                        sui_json_rpc_types::SuiTransactionBlockResponseOptions::new()
                            .with_effects(),
                    )
                    .await
                {
                    if let Some(effects) = tx_response.effects {
                        for obj_ref in effects.created().iter().chain(effects.mutated().iter()) {
                            all_object_ids.insert(obj_ref.reference.object_id);
                        }
                    }
                }
            }

            current_seq += 1;

            let processed = current_seq - start_seq;
            if processed % 100 == 0 {
                info!(
                    "Processed {}/{} checkpoints, found {} unique objects",
                    processed,
                    scan_range,
                    all_object_ids.len()
                );
            }
        }

        info!(
            "Found {} unique objects from {} checkpoints (range {} to {})",
            all_object_ids.len(),
            scan_range,
            start_seq,
            checkpoint_seq
        );

        self.fetch_objects_by_ids(client, all_object_ids.into_iter().collect())
            .await
    }

    async fn fetch_objects_by_ids(
        &self,
        client: &sui_sdk::SuiClient,
        object_ids: Vec<ObjectID>,
    ) -> Result<Vec<Object>> {
        let total = object_ids.len();
        info!("Fetching {} objects in batches of {}", total, BATCH_SIZE);

        let mut objects = Vec::new();
        for (i, chunk) in object_ids.chunks(BATCH_SIZE).enumerate() {
            let batch_num = i + 1;
            let total_batches = (total + BATCH_SIZE - 1) / BATCH_SIZE;

            info!(
                "Fetching batch {}/{} ({} objects)",
                batch_num,
                total_batches,
                chunk.len()
            );

            let responses = client
                .read_api()
                .multi_get_object_with_options(
                    chunk.to_vec(),
                    SuiObjectDataOptions::new()
                        .with_bcs()
                        .with_owner()
                        .with_type()
                        .with_previous_transaction(),
                )
                .await
                .context(format!("Failed to fetch batch {}", batch_num))?;

            for (obj_id, response) in chunk.iter().zip(responses.iter()) {
                match response.object() {
                    Ok(obj_data) => {
                        let protocol_config = ProtocolConfig::get_for_min_version();
                        match obj_data.clone().try_into_object(&protocol_config) {
                            Ok(object) => {
                                objects.push(object);
                            }
                            Err(e) => {
                                warn!("Failed to convert object {} to Object: {:?}", obj_id, e);
                            }
                        }
                    }
                    Err(e) => {
                        warn!("Failed to get object {}: {:?}", obj_id, e);
                    }
                }
            }

            if batch_num % 10 == 0 || batch_num == total_batches {
                info!(
                    "Progress: {}/{} batches completed, {} objects loaded",
                    batch_num,
                    total_batches,
                    objects.len()
                );
            }
        }

        info!("Successfully fetched {}/{} objects", objects.len(), total);

        Ok(objects)
    }
}

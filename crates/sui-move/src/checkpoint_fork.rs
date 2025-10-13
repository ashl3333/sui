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
        info!(
            "Fetching all objects modified up to checkpoint {}",
            checkpoint_seq
        );

        let mut all_object_ids = std::collections::HashSet::new();
        let mut current_seq = 0u64;

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

            if current_seq % 100 == 0 {
                info!(
                    "Processed {} checkpoints, found {} unique objects",
                    current_seq,
                    all_object_ids.len()
                );
            }
        }

        info!(
            "Found {} unique objects to fetch from {} checkpoints",
            all_object_ids.len(),
            checkpoint_seq + 1
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

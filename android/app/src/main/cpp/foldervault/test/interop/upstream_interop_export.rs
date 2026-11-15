//! Interop helper, not a regular test: when INTEROP_OUT is set, creates a vault on disk with upstream's own code
//! (config + encrypted/integrity block store + FsBlobStore) and writes a manifest of its contents, read back with
//! upstream's own reader, to $INTEROP_OUT/expected.txt. Used to check that another CryFS implementation can read it.
#![recursion_limit = "512"]

use cryfs_blobstore::{BlobId, BlobStoreOnBlocks};
use cryfs_blockstore::{
    AllowIntegrityViolations, DynBlockStore, IntegrityConfig, LLSharedBlockStore, LockingBlockStore,
    MissingBlockIsIntegrityViolation, OnDiskBlockStore,
};
use cryfs_cli_utils::setup_blockstore_stack_dyn;
use cryfs_config::{
    config::{CommandLineFlags, ConfigLoadResult, FixedPasswordProvider},
    localstate::LocalStateDir,
};
use cryfs_fsblobstore::fsblobstore::{EntryType, FsBlobStore};
use cryfs_utils::{
    async_drop::{AsyncDropGuard, SyncDrop},
    path::AbsolutePathBuf,
    progress::SilentProgressBarManager,
    with_async_drop,
};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

mod common;
#[allow(unused_imports)]
use common::fixture::FilesystemFixture; // the shared helpers refer to it via the crate root
use common::console::FixtureCreationConsole;
use common::entry_helpers::{self, CreatedDirBlob};

type Fs = FsBlobStore<BlobStoreOnBlocks<LockingBlockStore<DynBlockStore>>>;

async fn make_fs(
    store: &SyncDrop<LLSharedBlockStore<OnDiskBlockStore>>,
    config: &ConfigLoadResult,
    state: &LocalStateDir,
    missing_block: MissingBlockIsIntegrityViolation,
) -> AsyncDropGuard<Fs> {
    let locking = setup_blockstore_stack_dyn(
        LLSharedBlockStore::clone(store),
        &config.config.config(),
        config.my_client_id,
        state,
        IntegrityConfig {
            allow_integrity_violations: AllowIntegrityViolations::DontAllowViolations,
            missing_block_is_integrity_violation: missing_block,
            on_integrity_violation: Box::new(|err| panic!("INTEGRITY VIOLATION: {err:?}")),
        },
    )
    .await
    .expect("Failed to setup blockstore stack");
    let blobstore = BlobStoreOnBlocks::new(locking, config.config.config().blocksize)
        .await
        .expect("Failed to create blobstore");
    FsBlobStore::new(blobstore)
}

fn walk<'a>(
    fs: &'a Fs,
    dir_id: BlobId,
    path: String,
    out: &'a mut Vec<String>,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = ()> + 'a>> {
    Box::pin(async move {
        let mut blob = fs.load(&dir_id).await.unwrap().unwrap();
        let entries: Vec<(String, EntryType, BlobId)> = blob
            .as_dir()
            .unwrap()
            .entries()
            .map(|e| (e.name().to_string(), e.entry_type(), *e.blob_id()))
            .collect();
        blob.async_drop().await.unwrap();
        for (name, ty, id) in entries {
            let p = if path.is_empty() { name.clone() } else { format!("{path}/{name}") };
            match ty {
                EntryType::Dir => {
                    out.push(format!("D\t{p}"));
                    walk(fs, id, p, out).await;
                }
                EntryType::File => {
                    let mut b = fs.load(&id).await.unwrap().unwrap();
                    let f = b.as_file_mut().unwrap();
                    let n = f.num_bytes().await.unwrap() as usize;
                    let mut buf = vec![0u8; n];
                    let mut got = 0;
                    while got < n {
                        let k = f.try_read(&mut buf[got..], got as u64).await.unwrap();
                        assert!(k > 0, "short read");
                        got += k;
                    }
                    let hex: String = Sha256::digest(&buf).iter().map(|b| format!("{b:02x}")).collect();
                    out.push(format!("F\t{p}\t{n}\t{hex}"));
                    b.async_drop().await.unwrap();
                }
                EntryType::Symlink => {
                    let mut b = fs.load(&id).await.unwrap().unwrap();
                    let t = b.as_symlink_mut().unwrap().target().await.unwrap();
                    out.push(format!("L\t{p}\t{t}"));
                    b.async_drop().await.unwrap();
                }
            }
        }
    })
}

#[tokio::test(flavor = "multi_thread")]
async fn export_vault_and_manifest() {
    let Ok(out) = std::env::var("INTEROP_OUT") else { return };
    let out = PathBuf::from(out);
    let vault = out.join("vault");
    std::fs::create_dir_all(&vault).unwrap();
    let state = LocalStateDir::new(out.join("state"));

    let config = cryfs_config::config::create(
        vault.join("cryfs.config"),
        &FixedPasswordProvider::new("mypassword".to_owned()),
        &FixtureCreationConsole,
        &CommandLineFlags {
            missing_block_is_integrity_violation: Some(false),
            expected_cipher: std::env::var("INTEROP_CIPHER").ok(),
            blocksize: Some(byte_unit::Byte::from_u64(
                std::env::var("INTEROP_BLOCKSIZE").ok().and_then(|v| v.parse().ok()).unwrap_or(4096),
            )),
        },
        &state,
        true,
        SilentProgressBarManager,
    )
    .expect("Failed to create config");
    let root_id = BlobId::from_hex(&config.config.config().root_blob).unwrap();
    let store = SyncDrop::new(LLSharedBlockStore::new(OnDiskBlockStore::new(vault.clone())));

    {
        let fs = make_fs(&store, &config, &state, MissingBlockIsIntegrityViolation::IsAViolation).await;
        fs.create_root_dir_blob(&root_id).await.unwrap().async_drop().await.unwrap();
        let root_blob = fs.load(&root_id).await.unwrap().unwrap();
        let mut root = CreatedDirBlob::new(root_blob, AbsolutePathBuf::root());
        with_async_drop!(root, {
            let _ = entry_helpers::create_some_blobs(&fs, &mut root).await;
            Ok::<_, anyhow::Error>(())
        })
        .unwrap();
        fs.async_drop().await.unwrap();
    }
    {
        let fs = make_fs(&store, &config, &state, MissingBlockIsIntegrityViolation::IsAViolation).await;
        let mut lines = Vec::new();
        walk(&fs, root_id, String::new(), &mut lines).await;
        lines.sort();
        std::fs::write(out.join("expected.txt"), lines.join("\n") + "\n").unwrap();
        fs.async_drop().await.unwrap();
    }
    println!("cipher={} blocksize={}", config.config.config().cipher, config.config.config().blocksize);
}

/// Re-opens an existing vault (INTEROP_DUMP=<vault dir>, INTEROP_STATE=<upstream local state dir>) exactly like
/// the official client would -- with the integrity data it recorded when it wrote the blocks -- and writes the
/// manifest to $INTEROP_OUT/dump.txt. Any integrity violation (e.g. in blocks another client wrote) panics.
#[tokio::test(flavor = "multi_thread")]
async fn dump_vault_manifest() {
    let Ok(dir) = std::env::var("INTEROP_DUMP") else { return };
    let out = PathBuf::from(std::env::var("INTEROP_OUT").unwrap());
    let vault = PathBuf::from(dir);
    let state = LocalStateDir::new(PathBuf::from(std::env::var("INTEROP_STATE").unwrap()));
    let config = cryfs_config::config::load_readonly(
        vault.join("cryfs.config"),
        &FixedPasswordProvider::new("mypassword".to_owned()),
        &FixtureCreationConsole,
        &CommandLineFlags { missing_block_is_integrity_violation: None, expected_cipher: None, blocksize: None },
        &state,
        SilentProgressBarManager,
    )
    .expect("Failed to load config");
    let root_id = BlobId::from_hex(&config.config.config().root_blob).unwrap();
    let store = SyncDrop::new(LLSharedBlockStore::new(OnDiskBlockStore::new(vault.clone())));
    // Like the official client: a missing block is only a violation in single-client mode.
    let missing = if config.config.config().exclusive_client_id.is_some() {
        MissingBlockIsIntegrityViolation::IsAViolation
    } else {
        MissingBlockIsIntegrityViolation::IsNotAViolation
    };
    let fs = make_fs(&store, &config, &state, missing).await;
    let mut lines = Vec::new();
    walk(&fs, root_id, String::new(), &mut lines).await;
    lines.sort();
    std::fs::write(out.join("dump.txt"), lines.join("\n") + "\n").unwrap();
    fs.async_drop().await.unwrap();
}

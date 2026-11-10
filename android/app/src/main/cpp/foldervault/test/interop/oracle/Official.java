import java.io.*;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.*;
import java.util.*;
import org.cryptomator.cryptofs.*;
import org.cryptomator.cryptolib.api.*;
import org.cryptomator.cryptolib.common.MasterkeyFileAccess;
import org.cryptomator.cryptofs.migration.Migrators;
import org.cryptomator.cryptofs.migration.api.*;

/** Oracle: drives the OFFICIAL cryptofs (2.8.0, as shipped in Cryptomator CLI 0.6.2). */
public class Official {
    static final SecureRandom RNG = new SecureRandom();
    static final URI KEY_ID = URI.create("masterkeyfile:masterkey.cryptomator");

    static CryptoFileSystemProperties props(Path vault, String pw, CryptorProvider.Scheme scheme) {
        MasterkeyFileAccess mfa = new MasterkeyFileAccess(new byte[0], RNG);
        MasterkeyLoader loader = uri -> mfa.load(vault.resolve("masterkey.cryptomator"), pw);
        return CryptoFileSystemProperties.cryptoFileSystemProperties().withKeyLoader(loader).withCipherCombo(scheme).build();
    }

    public static void main(String[] a) throws Exception {
        String cmd = a[0];
        Path vault = Paths.get(a[1]);
        String pw = a[2];
        if (cmd.equals("create") || cmd.equals("create-ctrmac")) {
            CryptorProvider.Scheme sch = cmd.equals("create") ? CryptorProvider.Scheme.SIV_GCM : CryptorProvider.Scheme.SIV_CTRMAC;
            Files.createDirectories(vault);
            MasterkeyFileAccess mfa = new MasterkeyFileAccess(new byte[0], RNG);
            try (Masterkey mk = Masterkey.generate(RNG)) {
                mfa.persist(mk, vault.resolve("masterkey.cryptomator"), pw);
                CryptoFileSystemProperties p = CryptoFileSystemProperties.cryptoFileSystemProperties()
                        .withKeyLoader(u -> mk.copy()).withCipherCombo(sch).build();
                CryptoFileSystemProvider.initialize(vault, p, KEY_ID);
            }
            System.out.println("created");
            return;
        }
        if (cmd.equals("downgrade")) {   // make it a genuine format 7 vault: version-7 key file, no vault.cryptomator
            MasterkeyFileAccess mfa = new MasterkeyFileAccess(new byte[0], RNG);
            try (Masterkey mk = mfa.load(vault.resolve("masterkey.cryptomator"), pw)) {
                mfa.persist(mk, vault.resolve("masterkey.cryptomator"), pw, 7);
            }
            Files.deleteIfExists(vault.resolve("vault.cryptomator"));
            try (DirectoryStream<Path> ds = Files.newDirectoryStream(vault, "vault.cryptomator.*.bkup")) { for (Path b : ds) Files.delete(b); }
            System.out.println("downgraded");
            return;
        }
        if (cmd.equals("migrate")) {
            Migrators.get().migrate(vault, "vault.cryptomator", "masterkey.cryptomator", pw, MigrationProgressListener.IGNORE, e -> MigrationContinuationListener.ContinuationResult.PROCEED);
            System.out.println("migrated");
            return;
        }
        try (FileSystem fs = CryptoFileSystemProvider.newFileSystem(vault, props(vault, pw, CryptorProvider.Scheme.SIV_GCM))) {
            switch (cmd) {
                case "symlink": Files.createSymbolicLink(fs.getPath(a[3]), fs.getPath(a[4])); System.out.println("ok"); break;
                case "readlink": System.out.println(Files.readSymbolicLink(fs.getPath(a[3]))); break;
                case "mkdir": Files.createDirectories(fs.getPath(a[3])); break;
                case "put": Files.write(fs.getPath(a[3]), Files.readAllBytes(Paths.get(a[4]))); break;
                case "rm": Files.delete(fs.getPath(a[3])); break;
                case "mv": Files.move(fs.getPath(a[3]), fs.getPath(a[4])); break;
                case "mtime": System.out.println(Files.getLastModifiedTime(fs.getPath(a[3]), LinkOption.NOFOLLOW_LINKS).toMillis() / 1000); break;
                case "cat": System.out.write(Files.readAllBytes(fs.getPath(a[3]))); System.out.flush(); break;
                case "dump": dump(fs.getPath("/"), ""); break;
                default: System.err.println("unknown cmd"); System.exit(2);
            }
        }
    }

    static String sha(byte[] b) throws Exception {
        byte[] h = MessageDigest.getInstance("SHA-256").digest(b);
        StringBuilder sb = new StringBuilder(); for (int i = 0; i < 8; i++) sb.append(String.format("%02x", h[i])); return sb.toString();
    }

    static void dump(Path dir, String prefix) throws Exception {
        List<Path> kids = new ArrayList<>();
        try (DirectoryStream<Path> ds = Files.newDirectoryStream(dir)) { for (Path p : ds) kids.add(p); }
        kids.sort(Comparator.comparing(p -> p.getFileName().toString()));
        for (Path p : kids) {
            String name = prefix + "/" + p.getFileName();
            BasicFileAttributes at = Files.readAttributes(p, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (at.isSymbolicLink()) {
                System.out.println("L " + name + " -> " + Files.readSymbolicLink(p) + " " + at.size());
            } else if (at.isDirectory()) {
                System.out.println("D " + name);
                dump(p, name);
            } else {
                System.out.println("F " + name + " " + at.size() + " " + sha(Files.readAllBytes(p)));
            }
        }
    }
}

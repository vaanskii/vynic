/// Ed25519 public key that verifies developer unlock tokens.
///
/// Only the *public* half ships. Tokens are signed by `tool/dev_key.dart` with
/// the private key in `secrets/developer_signing_key.json`, which is gitignored
/// and never leaves the developer's machine. A client with the binary can read
/// this constant and learn nothing useful: verifying a signature is not the
/// same as being able to produce one.
///
/// Replacing this key invalidates every token signed with the old one, so a
/// rotation has to ship to every terminal before old builds stop being
/// serviceable. Regenerate only if the private key is actually compromised.
library;

const String kDeveloperPublicKeyBase64 =
    'bGacZBHy8joBMO8PoKbujLARv-oPIifHmRh4w1zuQlY=';

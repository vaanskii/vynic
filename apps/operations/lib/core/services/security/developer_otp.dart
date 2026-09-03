/// The end of the one-time-code chain, as shipped.
///
/// A terminal starts here and walks backwards, one link per code it accepts.
/// The tip is public by design — knowing it tells you nothing about which code
/// comes next, because getting there means inverting SHA-256.
///
/// Regenerate with `dart run tool/dev_key.dart otp-seed --force`, but only if
/// the seed in `secrets/developer_otp_seed.json` is lost or compromised:
/// terminals running the old build keep their old tip and stop accepting short
/// codes until they take a new build. Signed tokens keep working regardless,
/// which is the fallback if this ever goes wrong.
library;

const String kDeveloperOtpTip = 'JrsL8jR1e-Rkcg==';

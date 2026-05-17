///|
test "parse channel aliases" {
  assert_eq(parse_channel("stable"), Some(Stable))
  assert_eq(parse_channel("latest"), Some(Stable))
  assert_eq(parse_channel("nightly"), Some(Nightly))
  assert_eq(parse_channel("foo"), None)
}

///|
test "parse moon version output" {
  let output = "moon 0.1.20260310 (5eeec6b 2026-03-10)"
  assert_eq(parse_moon_version_id(output), Some("0.1.20260310"))
}

///|
test "extract version id from toolchain path" {
  let base = "/tmp/moonbee/toolchains"
  let p1 = "\{base}/0.1.20260310"
  let p2 = "\{base}/0.1.20260310/bin"
  assert_eq(version_from_toolchain_path(p1), Some("0.1.20260310"))
  assert_eq(version_from_toolchain_path(p2), Some("0.1.20260310"))
  assert_eq(version_from_toolchain_path("/tmp/other"), None)
}

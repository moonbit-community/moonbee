///|
test "parse channel aliases" {
  debug_inspect(parse_channel("stable"), content="Some(Stable)")
  debug_inspect(parse_channel("latest"), content="Some(Stable)")
  debug_inspect(parse_channel("nightly"), content="Some(Nightly)")
  debug_inspect(parse_channel("foo"), content="None")
}

///|
test "parse moon version output" {
  let output = "moon 0.1.20260310 (5eeec6b 2026-03-10)"
  debug_inspect(parse_moon_version_id(output), content="Some(\"0.1.20260310\")")
}

///|
test "extract version id from toolchain path" {
  let base = "/tmp/moonbee/toolchains"
  let p1 = "\{base}/0.1.20260310"
  let p2 = "\{base}/0.1.20260310/bin"
  debug_inspect(
    version_from_toolchain_path(p1),
    content="Some(\"0.1.20260310\")",
  )
  debug_inspect(
    version_from_toolchain_path(p2),
    content="Some(\"0.1.20260310\")",
  )
  debug_inspect(version_from_toolchain_path("/tmp/other"), content="None")
}

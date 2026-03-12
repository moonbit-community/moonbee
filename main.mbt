///|
pub(all) enum Channel {
  Stable
  Nightly
} derive(Eq, Show)

///|
struct Snapshot {
  toolchain_id : String
  version_id : String
  moon_version_all : String
  source_channel : String
  installed_at : UInt64
}

///|
fn main {
  @async.run_async_main(main_async)
}

///|
async fn main_async() -> Unit {
  let args = @env.args()
  maybe_run_first_run_bootstrap(args)

  if args.length() <= 1 {
    print_overview()
    return
  }

  match args[1] {
    "init" => init_entry(args)
    "install" => {
      if args.length() != 3 {
        fail_with_help(
          "install expects exactly one argument: stable or nightly",
        )
      }
      install_command(args[2])
    }
    "list" => {
      if args.length() != 2 {
        fail_with_help("list does not accept extra arguments")
      }
      list_command()
    }
    "uninstall" => uninstall_entry(args)
    "use" => use_entry(args)
    "nuke" => nuke_entry(args)
    "help" | "--help" | "-h" => print_help()
    _ => target_entry(args)
  }
}

///|
async fn print_overview() -> Unit {
  let snapshots = list_snapshots()
  let active_toolchain = detect_active_version()
  let moon_home = @sys.get_env_var("MOON_HOME").unwrap_or("<unset>")
  let moon_home_colored = colorize(moon_home, "35")
  let which_moon = resolve_which_moon()
  let which_moon_colored = colorize(which_moon, "35")
  let selectable_title = colorize("Selectable toolchains:", "1;34")
  let none_label = colorize("<none>", "90")
  let stable_shortcut = colorize("moonbee stable", "36")
  let nightly_shortcut = colorize("moonbee nightly", "36")

  print_bee_ascii()
  println("MOON_HOME: \{moon_home_colored}")
  println("which moon: \{which_moon_colored}")
  println("")
  println(selectable_title)
  if snapshots.length() == 0 {
    println("  \{none_label}")
  } else {
    for snapshot in snapshots {
      let tag = if active_toolchain == Some(snapshot.toolchain_id) {
        colorize(" [active]", "32")
      } else {
        ""
      }
      let use_cmd = colorize("moonbee \{snapshot.toolchain_id}", "36")
      let installed_label = format_installed_at_label(snapshot.installed_at)
      println("  - \{use_cmd}\{tag}")
      let version_parts = split_version_all_summary(snapshot.moon_version_all)
      if version_parts.length() == 0 {
        let unknown_line = colorize("<unknown>", "90")
        println("      \{unknown_line}")
      } else {
        let first_line = colorize(version_parts[0], "90")
        println("      \{first_line}")
        for i = 1; i < version_parts.length(); i = i + 1 {
          let part_line = colorize(version_parts[i], "90")
          println("      \{part_line}")
        }
      }
      let installed_line = colorize("installed \{installed_label}", "90")
      println("      \{installed_line}")
    }

    let stable_target = resolve_target_version("stable")
    if stable_target != None {
      println("  - \{stable_shortcut}")
      match stable_target {
        Some(target) => {
          let detail = colorize("      points to: \{target}", "90")
          println(detail)
        }
        None => ()
      }
    }
    let nightly_target = resolve_target_version("nightly")
    if nightly_target != None {
      println("  - \{nightly_shortcut}")
      match nightly_target {
        Some(target) => {
          let detail = colorize("      points to: \{target}", "90")
          println(detail)
        }
        None => ()
      }
    }
  }
  println("")
  println(colorize("Hint:", "33"))
  println(
    colorize(
      "Run `moonbee <toolchain-name>` to switch toolchains in current terminal.",
      "33",
    ),
  )
  println(colorize("Run `moonbee help` for more commands.", "33"))
}

///|
async fn resolve_which_moon() -> String {
  let (exit_code, stdout, _) = run_capture("which", ["moon"])
  if exit_code != 0 {
    return "<not found>"
  }

  let trimmed = stdout.trim().to_string()
  if trimmed == "" {
    return "<not found>"
  }

  match trimmed.split_once("\n") {
    Some((first, _)) => first.to_string()
    None => trimmed
  }
}

///|
fn should_skip_first_run_bootstrap(args : Array[String]) -> Bool {
  if args.length() > 1 {
    let cmd = args[1]
    if cmd == "nuke" ||
      cmd == "uninstall" ||
      cmd == "init" ||
      cmd == "help" ||
      cmd == "--help" ||
      cmd == "-h" {
      return true
    }
  }

  for i = 2; i < args.length(); i = i + 1 {
    if args[i] == "--emit-env" {
      return true
    }
  }
  false
}

///|
async fn maybe_run_first_run_bootstrap(args : Array[String]) -> Unit {
  if should_skip_first_run_bootstrap(args) {
    return
  }

  ensure_layout()
  if @xfs.path_exists(first_run_marker_file()) {
    return
  }

  run_first_setup()
}

///|
fn print_help() -> Unit {
  let snapshots = list_snapshots()
  let active_label = match detect_active_version() {
    Some(v) => render_snapshot_identity(snapshots, v)
    None => "<none>"
  }
  let title = colorize("moonbee - Manage MoonBit toolchain snapshots", "1;34")
  let section_current = colorize("Current toolchain:", "1;34")
  let section_usage = colorize("Usage:", "1;34")
  let section_commands = colorize("Commands:", "1;34")
  let section_notes = colorize("Notes:", "1;34")
  let active_value = colorize(active_label, "35")
  let cmd_init = colorize("moonbee init [--yes]", "36")
  let cmd_install = colorize("moonbee install <stable|nightly>", "36")
  let cmd_uninstall = colorize(
    "moonbee uninstall <toolchain_id|stable|nightly> [--yes]", "36",
  )
  let cmd_list = colorize("moonbee list", "36")
  let cmd_switch = colorize("moonbee <version_id|stable|nightly|clear>", "36")
  let cmd_switch_short = colorize("moonbee <toolchain_id|stable|nightly>", "36")
  let cmd_clear = colorize("moonbee clear", "36")
  let cmd_nuke = colorize("moonbee nuke [--yes]", "36")
  let cmd_help = colorize("moonbee help", "36")
  let note_line_1 = colorize(
    "- install resolves channel to concrete version snapshot", "90",
  )
  let note_line_2 = colorize(
    "- user-installed binaries are migrated to ~/.moonbee/bin on switch", "90",
  )
  let note_line_3 = colorize(
    "- shell integration makes 'moonbee <target>' work in current shell", "90",
  )
  let note_line_4 = colorize(
    "- nuke removes MOONBEE_HOME and injected shell integration block", "90",
  )

  print_bee_ascii()
  println(title)
  println("")
  println(section_current)
  println("  active  : \{active_value}")
  println("")
  println(section_usage)
  println("  \{cmd_init}")
  println("  \{cmd_install}")
  println("  \{cmd_uninstall}")
  println("  \{cmd_list}")
  println("  \{cmd_switch}")
  println("  \{cmd_nuke}")
  println("  \{cmd_help}")
  println("")
  println(section_commands)
  println("  \{cmd_init}  : run first setup; inject/update shell integration")
  println("  \{cmd_install}  : install latest channel build as a snapshot")
  println("  \{cmd_uninstall}  : remove one installed snapshot")
  println("  \{cmd_list}  : show installed snapshots and pointer status")
  println("  \{cmd_switch_short}  : switch current shell to target snapshot")
  println(
    "  \{cmd_clear}  : clear MOON_HOME/PATH override and return to global toolchain",
  )
  println(
    "  \{cmd_nuke}  : remove ~/.moonbee and injected shell integration block",
  )
  println("  \{cmd_help}  : show this help")
  println("")
  println(section_notes)
  println("  \{note_line_1}")
  println("  \{note_line_2}")
  println("  \{note_line_3}")
  println("  \{note_line_4}")
}

///|
fn fail_with_help(message : String) -> Unit {
  println("error: \{message}")
  println("")
  print_help()
  @sys.exit(1)
}

///|
fn print_bee_ascii() -> Unit {
  println("    __")
  println("   (  y--.")
  println(" \\ _\\/_,'")
  println("--(\"))))))=")
  println("   < > >")
  println("")
}

///|
async fn init_entry(args : Array[String]) -> Unit {
  let mut force = false

  for i = 2; i < args.length(); i = i + 1 {
    let arg = args[i]
    match arg {
      "--yes" | "-y" => force = true
      "--help" | "-h" => {
        println("Usage: moonbee init [--yes]")
        println("  Run first setup (shell integration)")
        return
      }
      _ => fail_with_help("unknown flag for init: \{arg}")
    }
  }

  run_first_setup(force_yes=force)
}

///|
async fn run_first_setup(force_yes? : Bool = false) -> Unit {
  ensure_layout()
  println("moonbee first-run setup:")
  println("  1. Inject shell integration for 'moonbee <target>/nuke'")

  let should_configure = if force_yes {
    true
  } else {
    ask_yes_no(
      "Run first-run setup now? (you can run 'moonbee init' later)",
      default_yes=true,
    )
  }

  if should_configure {
    ensure_shell_integration_non_interactive()
    println("First-run setup complete")
  } else {
    println("Skipped first-run setup")
  }

  write_text(first_run_marker_file(), "done\n")
}

///|
async fn use_entry(args : Array[String]) -> Unit {
  let mut target : String? = None
  let mut emit_env = false

  for i = 2; i < args.length(); i = i + 1 {
    let arg = args[i]
    match arg {
      "--emit-env" => emit_env = true
      "--help" | "-h" => {
        println("Usage: moonbee <version_id|stable|nightly|clear>")
        println("Legacy alias: moonbee use <version_id|stable|nightly|clear>")
        return
      }
      _ => {
        if arg.has_prefix("-") {
          fail_with_help("unknown flag for use: \{arg}")
        }
        match target {
          Some(_) => fail_with_help("use accepts at most one target")
          None => target = Some(arg)
        }
      }
    }
  }

  use_command(target, emit_env~)
}

///|
async fn target_entry(args : Array[String]) -> Unit {
  let target = args[1]
  let mut emit_env = false

  for i = 2; i < args.length(); i = i + 1 {
    let arg = args[i]
    match arg {
      "--emit-env" => emit_env = true
      "--help" | "-h" => {
        println("Usage: moonbee <version_id|stable|nightly|clear>")
        return
      }
      _ => fail_with_help("unknown flag for target switch: \{arg}")
    }
  }

  use_command(Some(target), emit_env~)
}

///|
async fn nuke_entry(args : Array[String]) -> Unit {
  let mut force = false
  let mut emit_env = false

  for i = 2; i < args.length(); i = i + 1 {
    let arg = args[i]
    match arg {
      "--yes" | "-y" => force = true
      "--emit-env" => emit_env = true
      "--help" | "-h" => {
        println("Usage: moonbee nuke [--yes]")
        println("  Remove MOONBEE_HOME and injected shell integration block")
        return
      }
      _ => fail_with_help("unknown flag for nuke: \{arg}")
    }
  }

  nuke_command(force~, emit_env~)
}

///|
async fn uninstall_entry(args : Array[String]) -> Unit {
  let mut force = false
  let mut emit_env = false
  let mut target : String? = None

  for i = 2; i < args.length(); i = i + 1 {
    let arg = args[i]
    match arg {
      "--yes" | "-y" => force = true
      "--emit-env" => emit_env = true
      "--help" | "-h" => {
        println(
          "Usage: moonbee uninstall <toolchain_id|stable|nightly> [--yes]",
        )
        println("  Remove one installed snapshot")
        return
      }
      _ => {
        if arg.has_prefix("-") {
          fail_with_help("unknown flag for uninstall: \{arg}")
        }
        match target {
          Some(_) => fail_with_help("uninstall accepts exactly one target")
          None => target = Some(arg)
        }
      }
    }
  }

  match target {
    Some(v) => uninstall_command(v, force~, emit_env~)
    None =>
      fail_with_help(
        "uninstall expects one target: toolchain_id, stable, or nightly",
      )
  }
}

///|
async fn install_command(channel_raw : String) -> Unit {
  ensure_layout()

  let mut channel = Stable
  match parse_channel(channel_raw) {
    Some(ch) => channel = ch
    None => {
      fail_with_help("install target must be stable or nightly")
      return
    }
  }

  let channel_name = channel_key(channel)
  let release_tag = if channel == Stable { "latest" } else { "nightly" }

  let tmp_root = path_join(tmp_dir(), "install-\{channel_name}-\{@env.now()}")
  let extract_dir = path_join(tmp_root, "extract")
  let install_script = path_join(tmp_root, "install.sh")

  ensure_dir(tmp_root)
  let script_url = official_install_script_url()

  println("Downloading official install script...")
  run_passthrough(
    "curl",
    [
      "--fail", "--location", "--progress-bar", "--output", install_script, script_url,
    ],
    log_cmd=true,
  )
  ignore(run_checked("chmod", ["+x", install_script], log_cmd=true))

  let install_path = build_install_script_path(extract_dir)
  println("Running official install script (\{release_tag})...")
  run_passthrough(
    "env",
    [
      "MOON_HOME=\{extract_dir}",
      "PATH=\{install_path}",
      "bash",
      install_script,
      release_tag,
    ],
    log_cmd=true,
  )

  let snapshot_env = build_snapshot_env(extract_dir)
  let moon_bin = path_join(path_join(extract_dir, "bin"), "moon")
  let version_output = run_checked(
    moon_bin,
    ["version"],
    extra_env=snapshot_env,
  )
  let (version_all_exit, version_all_stdout, _) = run_capture(
    moon_bin,
    ["version", "--all"],
    extra_env=snapshot_env,
  )
  let moon_version_all = if version_all_exit == 0 {
    summarize_multiline_output(version_all_stdout)
  } else {
    summarize_multiline_output(version_output)
  }

  let mut version_id = ""
  match parse_moon_version_id(version_output) {
    Some(v) => version_id = v
    None => {
      println("error: failed to parse version from 'moon version'")
      cleanup_dir(tmp_root)
      @sys.exit(1)
      return
    }
  }

  let toolchain_id = make_toolchain_id(version_id, channel_name)
  let final_snapshot = snapshot_dir(toolchain_id)
  if @xfs.path_exists(final_snapshot) {
    let reinstall = ask_yes_no(
      "Toolchain \{toolchain_id} already installed. Reinstall?",
      default_yes=false,
    )
    if not(reinstall) {
      write_text(channel_pointer_file(channel_name), toolchain_id + "\n")
      cleanup_dir(tmp_root)
      println(
        "Skipped reinstall, channel pointer updated: \{channel_name} -> \{toolchain_id}",
      )
      return
    }
    cleanup_dir(final_snapshot)
  }

  ensure_dir(toolchains_dir())
  ignore(run_checked("mv", [extract_dir, final_snapshot], log_cmd=true))
  repair_snapshot_bin_permissions(final_snapshot)
  match validate_snapshot(final_snapshot) {
    Some(reason) => {
      cleanup_dir(final_snapshot)
      cleanup_dir(tmp_root)
      println("error: installed snapshot is invalid: \{reason}")
      println("hint: retry install, or check moonbee tmp/install logs above")
      @sys.exit(1)
      return
    }
    None => ()
  }
  record_snapshot_bin_baseline(final_snapshot)

  let installed_at = @env.now()
  let meta = "toolchain_id=\{toolchain_id}\nversion_id=\{version_id}\nmoon_version_all=\{moon_version_all}\nsource_channel=\{channel_name}\ninstalled_at=\{installed_at}\n"
  write_text(snapshot_meta_file(final_snapshot), meta)

  write_text(channel_pointer_file(channel_name), toolchain_id + "\n")
  cleanup_dir(tmp_root)

  println(
    "Installed snapshot: \{toolchain_id} (moon=\{version_id}, source channel: \{channel_name})",
  )
}

///|
fn list_snapshots() -> Array[Snapshot] {
  if not(@xfs.path_exists(toolchains_dir())) {
    return []
  }

  let entries = @xfs.read_dir(toolchains_dir()) catch { _ => return [] }

  let snapshots : Array[Snapshot] = []

  for toolchain_id in entries {
    let snapshot_path = snapshot_dir(toolchain_id)
    let is_dir = @xfs.is_dir(snapshot_path) catch { _ => false }
    if not(is_dir) {
      continue
    }

    let mut version_id = toolchain_id
    let mut moon_version_all = ""
    let mut source_channel = "unknown"
    let mut installed_at : UInt64 = 0

    match read_text(snapshot_meta_file(snapshot_path)) {
      Some(content) =>
        for raw_line in content.split("\n") {
          let line = raw_line.trim().to_string()
          if line == "" {
            continue
          }
          match line.split_once("=") {
            Some((k, v)) => {
              let key = k.trim().to_string()
              let value = v.trim().to_string()
              match key {
                "version_id" => version_id = value
                "moon_version_all" =>
                  moon_version_all = summarize_multiline_output(value)
                "source_channel" => source_channel = value
                "installed_at" => {
                  let parsed = try? @strconv.parse_uint64(value)
                  match parsed {
                    Ok(n) => installed_at = n
                    Err(_) => ()
                  }
                }
                _ => ()
              }
            }
            None => ()
          }
        }
      None => ()
    }

    if moon_version_all == "" {
      moon_version_all = "moon \{version_id}"
    }

    snapshots.push({
      toolchain_id,
      version_id,
      moon_version_all,
      source_channel,
      installed_at,
    })
  }

  snapshots.sort_by((a, b) => {
    if a.installed_at > b.installed_at {
      -1
    } else if a.installed_at < b.installed_at {
      1
    } else {
      a.toolchain_id.compare(b.toolchain_id)
    }
  })

  snapshots
}

///|
fn find_snapshot_by_toolchain(
  snapshots : Array[Snapshot],
  toolchain_id : String,
) -> Snapshot? {
  for snapshot in snapshots {
    if snapshot.toolchain_id == toolchain_id {
      return Some(snapshot)
    }
  }
  None
}

///|
fn render_snapshot_identity(
  snapshots : Array[Snapshot],
  toolchain_id : String,
) -> String {
  match find_snapshot_by_toolchain(snapshots, toolchain_id) {
    Some(snapshot) => {
      let installed = format_installed_at_label(snapshot.installed_at)
      "\{snapshot.toolchain_id} (moon=\{snapshot.version_id}, channel=\{snapshot.source_channel}, installed=\{installed})"
    }
    None => toolchain_id
  }
}

///|
async fn list_command() -> Unit {
  ensure_layout()

  let snapshots = list_snapshots()
  let active_toolchain = detect_active_version()

  println("Moonbee home: \{moonbee_home()}")
  println("Toolchains dir: \{toolchains_dir()}")
  println("")

  if snapshots.length() == 0 {
    println("No installed snapshots")
  } else {
    println("Installed snapshots:")
    for snapshot in snapshots {
      let tags : Array[String] = []
      if active_toolchain == Some(snapshot.toolchain_id) {
        tags.push("active")
      }
      let tag_suffix = if tags.length() == 0 {
        ""
      } else {
        let joined = tags.join(", ")
        " [" + joined + "]"
      }
      let installed = format_installed_at_label(snapshot.installed_at)

      println(
        "  - \{snapshot.toolchain_id}\{tag_suffix} (moon=\{snapshot.version_id}, channel=\{snapshot.source_channel}, installed=\{installed})",
      )
    }
  }

  let stable_ptr = read_channel_pointer("stable").unwrap_or("<unset>")
  let nightly_ptr = read_channel_pointer("nightly").unwrap_or("<unset>")

  println("")
  println("Channel pointers:")
  println("  stable -> \{stable_ptr}")
  println("  nightly -> \{nightly_ptr}")
}

///|
async fn uninstall_command(
  target_raw : String,
  force? : Bool = false,
  emit_env? : Bool = false,
) -> Unit {
  ensure_layout()

  if is_clear_target(target_raw) {
    uninstall_log(
      "error: '\{target_raw}' is not uninstallable. Pick a snapshot, stable, or nightly.",
      emit_env~,
    )
    @sys.exit(1)
    return
  }

  let toolchain_id = match resolve_target_version(target_raw) {
    Some(v) => v
    None => {
      uninstall_log(
        "error: unknown uninstall target '\{target_raw}'",
        emit_env~,
      )
      uninstall_log(
        "hint: use full toolchain id, or run `moonbee list`",
        emit_env~,
      )
      @sys.exit(1)
      return
    }
  }

  let snapshot_path = snapshot_dir(toolchain_id)
  if not(@xfs.path_exists(snapshot_path)) {
    uninstall_log(
      "error: snapshot '\{toolchain_id}' is not installed",
      emit_env~,
    )
    @sys.exit(1)
    return
  }

  if detect_active_version() == Some(toolchain_id) {
    uninstall_log(
      "error: '\{toolchain_id}' is active in current shell; run `moonbee clear` or switch first",
      emit_env~,
    )
    @sys.exit(1)
    return
  }

  if not(force) {
    let confirmed = ask_yes_no(
      "Uninstall snapshot \{toolchain_id}?",
      default_yes=false,
    )
    if not(confirmed) {
      uninstall_log("Uninstall cancelled", emit_env~)
      if emit_env {
        print_noop_env_export()
      }
      return
    }
  }

  cleanup_dir(snapshot_path)
  uninstall_log("Uninstalled snapshot: \{toolchain_id}", emit_env~)

  let remaining = list_snapshots()
  refresh_channel_pointer_after_uninstall(
    "stable",
    toolchain_id,
    remaining,
    emit_env~,
  )
  refresh_channel_pointer_after_uninstall(
    "nightly",
    toolchain_id,
    remaining,
    emit_env~,
  )

  if emit_env {
    print_noop_env_export()
  }
}

///|
fn newest_snapshot_for_channel(
  snapshots : Array[Snapshot],
  channel_name : String,
) -> String? {
  for snapshot in snapshots {
    if snapshot.source_channel == channel_name {
      return Some(snapshot.toolchain_id)
    }
  }
  None
}

///|
async fn refresh_channel_pointer_after_uninstall(
  channel_name : String,
  removed_toolchain : String,
  remaining : Array[Snapshot],
  emit_env? : Bool = false,
) -> Unit {
  if read_channel_pointer(channel_name) != Some(removed_toolchain) {
    return
  }

  match newest_snapshot_for_channel(remaining, channel_name) {
    Some(next_toolchain) => {
      write_text(channel_pointer_file(channel_name), next_toolchain + "\n")
      uninstall_log(
        "Updated channel pointer: \{channel_name} -> \{next_toolchain}",
        emit_env~,
      )
    }
    None => {
      write_text(channel_pointer_file(channel_name), "\n")
      uninstall_log("Cleared channel pointer: \{channel_name}", emit_env~)
    }
  }
}

///|
async fn use_command(target_input : String?, emit_env~ : Bool) -> Unit {
  ensure_layout()

  let mut target = ""
  match target_input {
    Some(v) => target = v
    None =>
      match pick_snapshot_interactively() {
        Some(v) => target = v
        None => {
          println("No snapshot selected")
          @sys.exit(1)
          return
        }
      }
  }

  if is_clear_target(target) {
    let already_global = is_global_shell_state()
    let which_moon_after_clear = resolve_which_moon_after_clear()
    let clear_moon_home_line = "MOON_HOME: " + colorize("<unset>", "35")
    let clear_which_line = "which moon: " +
      colorize(which_moon_after_clear, "35")
    if emit_env {
      print_clear_moon_home_env_export()
      if already_global {
        @stdio.stderr.write(
          "Already using default toolchain in current shell\n",
        )
      } else {
        @stdio.stderr.write("Switched to default toolchain in current shell\n")
      }
      @stdio.stderr.write(clear_moon_home_line + "\n")
      @stdio.stderr.write(clear_which_line + "\n")
      return
    }

    if already_global {
      println("Already using default toolchain in current shell")
      println(clear_moon_home_line)
      println(clear_which_line)
      return
    }

    maybe_offer_shell_integration()
    println("Requested default toolchain")
    print_eval_hint_when_not_applied("moonbee clear --emit-env")
    return
  }

  let mut toolchain_id = ""
  match resolve_target_version(target) {
    Some(v) => toolchain_id = v
    None => {
      println("error: unknown target '\{target}', and no channel pointer found")
      println(
        "hint: if the same moon version exists in multiple channels, use:",
      )
      println("  - full toolchain id (e.g. 0.1.20260310-stable)")
      println("  - or run: moonbee list")
      @sys.exit(1)
      return
    }
  }

  let snapshot_path = snapshot_dir(toolchain_id)
  if not(@xfs.path_exists(snapshot_path)) {
    println("error: snapshot '\{toolchain_id}' is not installed")
    @sys.exit(1)
    return
  }

  match validate_snapshot(snapshot_path) {
    Some(reason) => {
      let hint = reinstall_hint_for_toolchain(toolchain_id)
      if emit_env {
        @stdio.stderr.write(
          "error: snapshot '\{toolchain_id}' is invalid: \{reason}\n",
        )
        @stdio.stderr.write("hint: reinstall it with: \{hint}\n")
      } else {
        println("error: snapshot '\{toolchain_id}' is invalid: \{reason}")
        println("hint: reinstall it with: \{hint}")
      }
      @sys.exit(1)
      return
    }
    None => ()
  }

  migrate_user_bins_on_switch(toolchain_id)

  let snapshot_bin = path_join(snapshot_path, "bin")
  let snapshot_moon = path_join(snapshot_bin, "moon")
  let switched_moon_home_line = "MOON_HOME: " + colorize(snapshot_path, "35")
  let switched_which_line = "which moon: " + colorize(snapshot_moon, "35")

  let already_active = @sys.get_env_var("MOON_HOME") == Some(snapshot_path)
  if emit_env {
    print_env_export(snapshot_path)
    if already_active {
      @stdio.stderr.write("Selected snapshot already active: \{toolchain_id}\n")
    } else {
      @stdio.stderr.write("Switched to snapshot: \{toolchain_id}\n")
    }
    @stdio.stderr.write(switched_moon_home_line + "\n")
    @stdio.stderr.write(switched_which_line + "\n")
    return
  }

  if already_active {
    println("Selected snapshot already active: \{toolchain_id}")
    println(switched_moon_home_line)
    println(switched_which_line)
    return
  }

  maybe_offer_shell_integration()

  println("Selected snapshot: \{toolchain_id}")
  print_eval_hint_when_not_applied("moonbee \{toolchain_id} --emit-env")
}

///|
fn resolve_target_version(raw : String) -> String? {
  let normalized = raw.trim().to_string()

  match parse_channel(normalized) {
    Some(channel) => {
      let pointed = read_channel_pointer(channel_key(channel))
      match pointed {
        Some(toolchain_id) =>
          if @xfs.path_exists(snapshot_dir(toolchain_id)) {
            Some(toolchain_id)
          } else {
            resolve_toolchain_by_moon_version(toolchain_id)
          }
        None => None
      }
    }
    None => {
      let candidate = snapshot_dir(normalized)
      if @xfs.path_exists(candidate) {
        Some(normalized)
      } else {
        resolve_toolchain_by_moon_version(normalized)
      }
    }
  }
}

///|
async fn resolve_which_moon_after_clear() -> String {
  let old_path = @sys.get_env_var("PATH").unwrap_or("")
  let filtered_path = filter_path_for_clear(old_path)
  let path_for_lookup = if filtered_path == "" {
    default_system_path()
  } else {
    filtered_path
  }

  match find_executable_in_path("moon", path_for_lookup) {
    Some(path) => path
    None => "<not found>"
  }
}

///|
fn filter_path_for_clear(path_value : String) -> String {
  let moonbee_bin = shared_bin_dir()
  let moonbee_toolchains_prefix = toolchains_dir() + "/"

  let kept : Array[String] = []
  for raw_entry in path_value.split(":") {
    let entry = raw_entry.to_string()
    if entry == "" {
      continue
    }
    if entry == moonbee_bin {
      continue
    }
    if entry.has_prefix(moonbee_toolchains_prefix) && entry.has_suffix("/bin") {
      continue
    }
    kept.push(entry)
  }

  kept.join(":")
}

///|
async fn find_executable_in_path(name : String, path_value : String) -> String? {
  for raw_dir in path_value.split(":") {
    let dir = raw_dir.to_string()
    if dir == "" {
      continue
    }
    let candidate = path_join(dir, name)
    if is_executable_file(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn is_clear_target(raw : String) -> Bool {
  let normalized = raw.trim().to_lower()
  normalized == "clear" || normalized == "global" || normalized == "system"
}

///|
fn is_global_shell_state() -> Bool {
  match @sys.get_env_var("MOON_HOME") {
    Some(v) => if v.trim().to_string() != "" { return false }
    None => ()
  }

  let path_value = @sys.get_env_var("PATH").unwrap_or("")
  not(path_contains_moonbee_entries(path_value))
}

///|
fn path_contains_moonbee_entries(path_value : String) -> Bool {
  let moonbee_bin = path_join(moonbee_home(), "bin")
  let moonbee_toolchains = path_join(moonbee_home(), "toolchains") + "/"
  path_value.contains(moonbee_bin) || path_value.contains(moonbee_toolchains)
}

///|
fn color_enabled() -> Bool {
  let no_color = @sys.get_env_var("NO_COLOR").unwrap_or("")
  if no_color != "" {
    return false
  }

  let term = @sys.get_env_var("TERM").unwrap_or("")
  term != "dumb"
}

///|
fn colorize(text : String, code : String) -> String {
  if not(color_enabled()) {
    return text
  }
  "\u{1b}[\{code}m\{text}\u{1b}[0m"
}

///|
fn print_eval_hint_when_not_applied(emit_cmd : String) -> Unit {
  println(
    colorize(
      "warning: current shell is not switched yet. Apply this once:", "33",
    ),
  )
  println("  eval \"$(\{emit_cmd})\"")
  match detect_shell_rc_file() {
    Some(rc) =>
      println(
        "If you already enabled shell integration but it still does not work, run: source \{rc}",
      )
    None => ()
  }
}

///|
fn resolve_toolchain_by_moon_version(version_id : String) -> String? {
  let snapshots = list_snapshots()
  let matched : Array[Snapshot] = []

  for snapshot in snapshots {
    if snapshot.version_id == version_id {
      matched.push(snapshot)
    }
  }

  if matched.length() == 1 {
    return Some(matched[0].toolchain_id)
  }

  None
}

///|
fn reinstall_hint_for_toolchain(toolchain_id : String) -> String {
  let snapshots = list_snapshots()
  match find_snapshot_by_toolchain(snapshots, toolchain_id) {
    Some(snapshot) =>
      if snapshot.source_channel == "stable" ||
        snapshot.source_channel == "nightly" {
        "moonbee install " + snapshot.source_channel
      } else {
        "moonbee install stable|nightly"
      }
    None => "moonbee install stable|nightly"
  }
}

///|
async fn validate_snapshot(snapshot_path : String) -> String? {
  let moon_bin = path_join(path_join(snapshot_path, "bin"), "moon")
  if not(@xfs.path_exists(moon_bin)) {
    return Some("missing bin/moon")
  }
  if not(is_executable_file(moon_bin)) {
    return Some("bin/moon is not executable")
  }

  let core_dir = path_join(path_join(snapshot_path, "lib"), "core")
  if not(@xfs.path_exists(core_dir)) {
    return Some("missing lib/core")
  }
  let core_is_dir = @xfs.is_dir(core_dir) catch { _ => false }
  if not(core_is_dir) {
    return Some("lib/core is not a directory")
  }

  None
}

///|
async fn is_executable_file(path : String) -> Bool {
  let (exit_code, _, _) = run_capture("test", ["-x", path])
  exit_code == 0
}

///|
async fn pick_snapshot_interactively() -> String? {
  let snapshots = list_snapshots()
  if snapshots.length() == 0 {
    @stdio.stderr.write("No installed snapshots. Run: moonbee install stable\n")
    return None
  }

  let active_version = detect_active_version()

  @stdio.stderr.write("Current toolchain:\n")
  match active_version {
    Some(v) =>
      @stdio.stderr.write(
        "  active  : \{render_snapshot_identity(snapshots, v)}\n",
      )
    None => @stdio.stderr.write("  active  : <none>\n")
  }
  @stdio.stderr.write("\n")

  @stdio.stderr.write("Pick a snapshot to use:\n")
  for idx = 0; idx < snapshots.length(); idx = idx + 1 {
    let snap = snapshots[idx]
    let installed = format_installed_at_label(snap.installed_at)
    @stdio.stderr.write(
      "  \{idx + 1}. \{snap.toolchain_id} (moon=\{snap.version_id}, channel=\{snap.source_channel}, installed=\{installed})",
    )
    @stdio.stderr.write("\n")
  }

  while true {
    @stdio.stderr.write("Enter number: ")
    let text = match @stdio.stdin.read_until("\n") {
      Some(v) => v.trim().to_string()
      None => return None
    }

    if text == "" {
      continue
    }

    let parsed = try? @strconv.parse_int(text)
    let idx = match parsed {
      Ok(v) => v
      Err(_) => {
        @stdio.stderr.write("Invalid number\n")
        continue
      }
    }

    if idx < 1 || idx > snapshots.length() {
      @stdio.stderr.write("Out of range\n")
      continue
    }

    return Some(snapshots[idx - 1].toolchain_id)
  }

  None
}

///|
async fn ask_yes_no(question : String, default_yes? : Bool = true) -> Bool {
  let hint = if default_yes { "[Y/n]" } else { "[y/N]" }

  while true {
    @stdio.stderr.write("\{question} \{hint} ")
    let answer = match @stdio.stdin.read_until("\n") {
      Some(v) => v.trim().to_lower()
      None => return default_yes
    }

    if answer == "" {
      return default_yes
    }
    if answer == "y" || answer == "yes" {
      return true
    }
    if answer == "n" || answer == "no" {
      return false
    }

    @stdio.stderr.write("Please answer y or n\n")
  }

  default_yes
}

///|
fn string_array_contains(xs : Array[String], needle : String) -> Bool {
  for x in xs {
    if x == needle {
      return true
    }
  }
  false
}

///|
fn read_snapshot_bin_baseline(snapshot_path : String) -> Array[String]? {
  match read_text(snapshot_bin_baseline_file(snapshot_path)) {
    Some(content) => {
      let items : Array[String] = []
      for raw in content.split("\n") {
        let item = raw.trim().to_string()
        if item != "" {
          items.push(item)
        }
      }
      Some(items)
    }
    None => None
  }
}

///|
fn record_snapshot_bin_baseline(snapshot_path : String) -> Unit {
  let bin_dir = snapshot_bin_dir(snapshot_path)
  if not(@xfs.path_exists(bin_dir)) {
    println("error: missing bin directory in snapshot: \{bin_dir}")
    @sys.exit(1)
    return
  }

  let entries = @xfs.read_dir(bin_dir) catch {
    err => {
      println("error: failed to read snapshot bin '\{bin_dir}': \{err}")
      @sys.exit(1)
      []
    }
  }
  entries.sort()

  let text = if entries.length() == 0 { "" } else { entries.join("\n") + "\n" }
  write_text(snapshot_bin_baseline_file(snapshot_path), text)
}

///|
fn choose_shared_bin_destination(
  name : String,
  source_version : String,
) -> String {
  let base = path_join(shared_bin_dir(), name)
  if not(@xfs.path_exists(base)) {
    return base
  }

  let with_version = path_join(shared_bin_dir(), name + "." + source_version)
  if not(@xfs.path_exists(with_version)) {
    return with_version
  }

  path_join(
    shared_bin_dir(),
    name + "." + source_version + "." + "\{@env.now()}",
  )
}

///|
async fn migrate_user_bins_on_switch(target_version : String) -> Unit {
  let active = detect_active_version()
  let active_version = match active {
    Some(v) => v
    None => return
  }

  if active_version == target_version {
    return
  }

  let source_snapshot = snapshot_dir(active_version)
  if not(@xfs.path_exists(source_snapshot)) {
    return
  }

  let baseline = match read_snapshot_bin_baseline(source_snapshot) {
    Some(items) => items
    None => {
      @stdio.stderr.write(
        "warning: skip user-bin migration for \{active_version}: missing baseline file\n",
      )
      return
    }
  }

  let source_bin = snapshot_bin_dir(source_snapshot)
  let entries = @xfs.read_dir(source_bin) catch { _ => return }

  ensure_dir(shared_bin_dir())

  let moved : Array[String] = []
  for name in entries {
    if string_array_contains(baseline, name) {
      continue
    }

    let source_path = path_join(source_bin, name)
    let is_regular = @xfs.is_file(source_path) catch { _ => false }
    let is_link = is_symbolic_link(source_path)
    if not(is_regular) && not(is_link) {
      continue
    }

    let dest_path = choose_shared_bin_destination(name, active_version)
    ignore(run_checked("mv", [source_path, dest_path]))
    moved.push(name)
  }

  if moved.length() == 0 {
    return
  }

  @stdio.stderr.write(
    "warning: moved \{moved.length()} user-installed binaries from \{active_version} to \{shared_bin_dir()}\n",
  )
  for name in moved {
    @stdio.stderr.write("  - \{name}\n")
  }
}

///|
async fn repair_snapshot_bin_permissions(snapshot_path : String) -> Unit {
  let bin_dir = snapshot_bin_dir(snapshot_path)
  if not(@xfs.path_exists(bin_dir)) {
    return
  }

  let entries = @xfs.read_dir(bin_dir) catch { _ => return }
  for name in entries {
    let entry = path_join(bin_dir, name)
    let is_file = @xfs.is_file(entry) catch { _ => false }
    if not(is_file) {
      continue
    }
    ignore(run_capture("chmod", ["+x", entry]))
  }
}

///|
fn build_snapshot_env(snapshot_path : String) -> Map[String, String] {
  let snapshot_bin = path_join(snapshot_path, "bin")
  let shared_bin = shared_bin_dir()
  let old_path = @sys.get_env_var("PATH").unwrap_or("")
  let prefix = "\{snapshot_bin}:\{shared_bin}"
  let joined_path = if old_path == "" {
    prefix
  } else {
    "\{prefix}:\{old_path}"
  }
  { "MOON_HOME": snapshot_path, "PATH": joined_path }
}

///|
fn build_install_script_path(snapshot_path : String) -> String {
  let snapshot_bin = path_join(snapshot_path, "bin")
  let old_path = @sys.get_env_var("PATH").unwrap_or("")
  let filtered = filter_install_base_path(old_path)
  if filtered == "" {
    "\{snapshot_bin}:\{default_system_path()}"
  } else {
    "\{snapshot_bin}:\{filtered}"
  }
}

///|
fn filter_install_base_path(path_value : String) -> String {
  let home_moon_bin = path_join(home_dir(), ".moon/bin")
  let moonbee_bin = shared_bin_dir()
  let moonbee_toolchains_prefix = toolchains_dir() + "/"
  let current_moon_home = @sys.get_env_var("MOON_HOME").unwrap_or("")
  let current_moon_home_bin = if current_moon_home.trim().to_string() == "" {
    ""
  } else {
    path_join(current_moon_home, "bin")
  }

  let kept : Array[String] = []
  for raw in path_value.split(":") {
    let entry = raw.trim().to_string()
    if entry == "" {
      continue
    }
    if entry == moonbee_bin {
      continue
    }
    if entry == home_moon_bin {
      continue
    }
    if current_moon_home_bin != "" && entry == current_moon_home_bin {
      continue
    }
    if entry.has_prefix(moonbee_toolchains_prefix) && entry.has_suffix("/bin") {
      continue
    }
    if string_array_contains(kept, entry) {
      continue
    }
    kept.push(entry)
  }

  kept.join(":")
}

///|
fn default_system_path() -> String {
  "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

///|
fn official_install_script_url() -> String {
  match @sys.get_env_var("MOONBEE_INSTALL_SCRIPT_URL") {
    Some(v) => {
      let trimmed = v.trim().to_string()
      if trimmed == "" {
        "https://cli.moonbitlang.com/install/unix.sh"
      } else {
        trimmed
      }
    }
    None => "https://cli.moonbitlang.com/install/unix.sh"
  }
}

///|
async fn run_capture(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  cwd? : String = "",
) -> (Int, String, String) {
  let result = if cwd == "" {
    try? @process.collect_output(cmd, args, extra_env~, inherit_env=true)
  } else {
    try? @process.collect_output(cmd, args, extra_env~, inherit_env=true, cwd~)
  }

  match result {
    Ok((exit_code, stdout_data, stderr_data)) =>
      (exit_code, stdout_data.text(), stderr_data.text())
    Err(err) => {
      println("error: failed to run command '\{cmd}': \{err}")
      @sys.exit(1)
      (1, "", "")
    }
  }
}

///|
async fn run_passthrough(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  cwd? : String = "",
  log_cmd? : Bool = false,
) -> Unit {
  let joined_args = args.join(" ")
  let rendered = if joined_args == "" { cmd } else { cmd + " " + joined_args }
  if log_cmd {
    println("$ \{rendered}")
  }

  let result = if cwd == "" {
    try? @process.run(
      cmd,
      args,
      extra_env~,
      inherit_env=true,
      stdout=@stdio.stdout,
      stderr=@stdio.stderr,
    )
  } else {
    try? @process.run(
      cmd,
      args,
      extra_env~,
      inherit_env=true,
      stdout=@stdio.stdout,
      stderr=@stdio.stderr,
      cwd~,
    )
  }

  match result {
    Ok(exit_code) =>
      if exit_code != 0 {
        println("error: command failed: \{rendered}")
        @sys.exit(exit_code)
      }
    Err(err) => {
      println("error: failed to run command '\{cmd}': \{err}")
      @sys.exit(1)
    }
  }
}

///|
async fn run_checked(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  cwd? : String = "",
  log_cmd? : Bool = false,
) -> String {
  let joined_args = args.join(" ")
  let rendered = if joined_args == "" { cmd } else { cmd + " " + joined_args }
  if log_cmd {
    println("$ \{rendered}")
  }

  let (exit_code, stdout, stderr) = run_capture(cmd, args, extra_env~, cwd~)

  if exit_code != 0 {
    println("error: command failed: \{rendered}")
    if stdout.trim() != "" {
      println("stdout:\n\{stdout}")
    }
    if stderr.trim() != "" {
      println("stderr:\n\{stderr}")
    }
    @sys.exit(exit_code)
  }

  if log_cmd {
    let out = stdout.trim()
    let err = stderr.trim()
    if out != "" {
      println(out)
    }
    if err != "" {
      println(err)
    }
  }

  stdout
}

///|
pub fn parse_channel(raw : String) -> Channel? {
  match raw.to_lower() {
    "stable" => Some(Stable)
    "latest" => Some(Stable)
    "nightly" => Some(Nightly)
    _ => None
  }
}

///|
fn channel_key(channel : Channel) -> String {
  match channel {
    Stable => "stable"
    Nightly => "nightly"
  }
}

///|
fn make_toolchain_id(version_id : String, channel_name : String) -> String {
  version_id + "-" + channel_name
}

///|
pub fn parse_moon_version_id(version_output : String) -> String? {
  for raw_line in version_output.split("\n") {
    let line = raw_line.trim().to_string()
    if not(line.has_prefix("moon ")) {
      continue
    }

    let suffix = match line.strip_prefix("moon ") {
      Some(rest) => rest.to_string()
      None => continue
    }

    match suffix.split_once(" ") {
      Some((version, _rest)) => {
        let v = version.trim().to_string()
        if v != "" {
          return Some(v)
        }
      }
      None => {
        let v = suffix.trim().to_string()
        if v != "" {
          return Some(v)
        }
      }
    }
  }

  None
}

///|
fn summarize_multiline_output(raw : String) -> String {
  let parts = extract_primary_version_parts(raw)
  if parts.length() == 0 {
    "<unknown>"
  } else {
    parts.join(" | ")
  }
}

///|
fn split_version_all_summary(summary : String) -> Array[String] {
  let parts : Array[String] = []
  for segment in summary.split(" | ") {
    let item = segment.trim().to_string()
    if item != "" {
      parts.push(item)
    }
  }
  parts
}

///|
fn extract_primary_version_parts(raw : String) -> Array[String] {
  let mut moon = ""
  let mut moonc = ""
  let mut moonrun = ""

  for raw_line in raw.split("\n") {
    for raw_segment in raw_line.split("|") {
      let segment = raw_segment.trim().to_string()
      if segment == "" {
        continue
      }

      let sanitized = sanitize_version_all_line(segment)
      if sanitized.has_prefix("moon ") && moon == "" {
        moon = sanitized
        continue
      }
      if sanitized.has_prefix("moonc ") && moonc == "" {
        moonc = sanitized
        continue
      }
      if sanitized.has_prefix("moonrun ") && moonrun == "" {
        moonrun = sanitized
        continue
      }
    }
  }

  let parts : Array[String] = []
  if moon != "" {
    parts.push(moon)
  }
  if moonc != "" {
    parts.push(moonc)
  }
  if moonrun != "" {
    parts.push(moonrun)
  }
  parts
}

///|
fn sanitize_version_all_line(line : String) -> String {
  let kept : Array[String] = []
  for token_raw in line.split(" ") {
    let token = token_raw.trim().to_string()
    if token == "" {
      continue
    }
    if looks_like_path_token(token) {
      continue
    }
    kept.push(token)
  }

  if kept.length() == 0 {
    line
  } else {
    kept.join(" ")
  }
}

///|
fn looks_like_path_token(token : String) -> Bool {
  if token.has_prefix("/") ||
    token.has_prefix("~/") ||
    token.has_prefix("./") ||
    token.has_prefix("../") {
    return token.contains("/")
  }
  false
}

///|
fn format_installed_at_label(installed_at : UInt64) -> String {
  if installed_at == 0 {
    return "<unknown>"
  }

  let now = @env.now()
  if now <= installed_at {
    return "just now"
  }

  let diff = now - installed_at
  let minute : UInt64 = 60_000
  let hour : UInt64 = 60 * minute
  let day : UInt64 = 24 * hour
  let month : UInt64 = 30 * day
  let year : UInt64 = 365 * day

  if diff < minute {
    return "just now"
  }
  if diff < hour {
    return "\{diff / minute}m ago"
  }
  if diff < day {
    return "\{diff / hour}h ago"
  }
  if diff < month {
    return "\{diff / day}d ago"
  }
  if diff < year {
    return "\{diff / month}mo ago"
  }
  "\{diff / year}y ago"
}

///|
fn read_text(path : String) -> String? {
  if not(@xfs.path_exists(path)) {
    return None
  }

  let result = try? @xfs.read_file_to_string(path)
  match result {
    Ok(content) => Some(content)
    Err(_) => None
  }
}

///|
fn write_text(path : String, content : String) -> Unit {
  let result = try? @xfs.write_string_to_file(path, content)
  match result {
    Ok(_) => ()
    Err(err) => {
      println("error: failed to write '\{path}': \{err}")
      @sys.exit(1)
    }
  }
}

///|
async fn ensure_dir(path : String) -> Unit {
  if @xfs.path_exists(path) {
    let is_dir = @xfs.is_dir(path) catch { _ => false }
    if is_dir {
      return
    }
    println("error: path exists but is not a directory: '\{path}'")
    @sys.exit(1)
    return
  }

  let result = try? @afs.mkdir(path, permission=0o755, recursive=true)
  match result {
    Ok(_) => ()
    Err(err) => {
      if @xfs.path_exists(path) {
        let is_dir = @xfs.is_dir(path) catch { _ => false }
        if is_dir {
          return
        }
      }
      println("error: failed to create directory '\{path}': \{err}")
      @sys.exit(1)
    }
  }
}

///|
async fn cleanup_dir(path : String) -> Unit {
  if not(@xfs.path_exists(path)) {
    return
  }

  let result = try? @afs.rmdir(path, recursive=true)
  match result {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
async fn ensure_layout() -> Unit {
  ensure_dir(moonbee_home())
  ensure_dir(toolchains_dir())
  ensure_dir(channels_dir())
  ensure_dir(shared_bin_dir())
  ensure_dir(tmp_dir())
}

///|
fn read_channel_pointer(channel_name : String) -> String? {
  match read_text(channel_pointer_file(channel_name)) {
    Some(v) => {
      let trimmed = v.trim().to_string()
      if trimmed == "" {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
pub fn version_from_toolchain_path(path : String) -> String? {
  let normalized = path.trim().to_string()
  let marker = "/toolchains/"

  let remaining = match normalized.split_once(marker) {
    Some((_before, after)) => after.to_string()
    None => {
      let prefix = toolchains_dir() + "/"
      match normalized.strip_prefix(prefix) {
        Some(rest) => rest.to_string()
        None => return None
      }
    }
  }

  if remaining == "" {
    return None
  }

  match remaining.split_once("/") {
    Some((v, _)) => Some(v.to_string())
    None => Some(remaining)
  }
}

///|
fn detect_active_version() -> String? {
  match @sys.get_env_var("MOON_HOME") {
    Some(current_home) => version_from_toolchain_path(current_home)
    None => None
  }
}

///|
async fn is_symbolic_link(path : String) -> Bool {
  let (exit_code, _, _) = run_capture("test", ["-L", path])
  exit_code == 0
}

///|
async fn maybe_offer_shell_integration() -> Unit {
  let rc = match detect_shell_rc_file() {
    Some(p) => p
    None => return
  }

  let current = read_text(rc).unwrap_or("")
  let has_block = current.contains(shell_marker_start()) &&
    current.contains(shell_marker_end())

  if has_block {
    let supports_shortcut = shell_integration_is_current(current)
    if supports_shortcut {
      return
    }

    let should_upgrade = ask_yes_no(
      "Shell integration in \{rc} is outdated. Update it now?",
      default_yes=true,
    )
    if not(should_upgrade) {
      return
    }

    let (stripped, _) = strip_shell_integration_blocks(current)
    let next = append_shell_integration_block(stripped)
    write_text(rc, next)
    println("Shell integration updated in \{rc}")
    println("Run: source \{rc}")
    return
  }

  let should_install = ask_yes_no(
    "Shell integration not found. Append moonbee init block to \{rc}?",
    default_yes=true,
  )
  if not(should_install) {
    return
  }

  let next = append_shell_integration_block(current)
  write_text(rc, next)
  println("Shell integration appended to \{rc}")
  println("Run: source \{rc}")
}

///|
fn append_shell_integration_block(current : String) -> String {
  let mut next = current
  if next.trim() != "" && not(next.has_suffix("\n")) {
    next = next + "\n"
  }
  if not(next.has_suffix("\n\n")) {
    next = next + "\n"
  }
  next + shell_integration_block()
}

///|
fn shell_integration_is_current(content : String) -> Bool {
  content.contains(shell_integration_version_tag()) &&
  content.contains("command moonbee \"$__target\" --emit-env")
}

///|
fn shell_integration_version_tag() -> String {
  "# moonbee-shell-v2"
}

///|
fn ensure_shell_integration_non_interactive() -> Unit {
  let rc = match detect_shell_rc_file() {
    Some(p) => p
    None => {
      println("Skip shell integration: unsupported shell")
      return
    }
  }

  let current = read_text(rc).unwrap_or("")
  let has_block = current.contains(shell_marker_start()) &&
    current.contains(shell_marker_end())

  if has_block {
    let supports_shortcut = shell_integration_is_current(current)
    if supports_shortcut {
      println("Shell integration already configured in \{rc}")
      return
    }

    let (stripped, _) = strip_shell_integration_blocks(current)
    let next = append_shell_integration_block(stripped)
    write_text(rc, next)
    println("Shell integration updated in \{rc}")
    println("Run: source \{rc}")
    return
  }

  let next = append_shell_integration_block(current)
  write_text(rc, next)
  println("Shell integration appended to \{rc}")
  println("Run: source \{rc}")
}

///|
async fn nuke_command(force? : Bool = false, emit_env? : Bool = false) -> Unit {
  let target_home = moonbee_home()
  let zshrc = path_join(home_dir(), ".zshrc")
  let bashrc = path_join(home_dir(), ".bashrc")

  nuke_log("moonbee nuke will:", emit_env~)
  nuke_log("  1. Remove managed directory: \{target_home}", emit_env~)
  nuke_log("  2. Remove injected moonbee shell block from: \{zshrc}", emit_env~)
  nuke_log(
    "  3. Remove injected moonbee shell block from: \{bashrc}",
    emit_env~,
  )

  if not(force) {
    let confirmed = ask_yes_no("Continue?", default_yes=false)
    if not(confirmed) {
      nuke_log("Nuke cancelled", emit_env~)
      return
    }
  }

  let removed_zsh = remove_shell_integration_from_file(zshrc)
  let removed_bash = remove_shell_integration_from_file(bashrc)

  if @xfs.path_exists(target_home) {
    cleanup_dir(target_home)
    nuke_log("Removed: \{target_home}", emit_env~)
  } else {
    nuke_log("Already absent: \{target_home}", emit_env~)
  }

  if removed_zsh {
    nuke_log("Removed moonbee shell block from: \{zshrc}", emit_env~)
  }
  if removed_bash {
    nuke_log("Removed moonbee shell block from: \{bashrc}", emit_env~)
  }
  if not(removed_zsh) && not(removed_bash) {
    nuke_log(
      "No injected shell block found in ~/.zshrc or ~/.bashrc",
      emit_env~,
    )
  }

  if emit_env {
    print_nuke_env_export()
  }
}

///|
async fn nuke_log(message : String, emit_env? : Bool = false) -> Unit {
  if emit_env {
    @stdio.stderr.write(message + "\n")
  } else {
    println(message)
  }
}

///|
async fn uninstall_log(message : String, emit_env? : Bool = false) -> Unit {
  if emit_env {
    @stdio.stderr.write(message + "\n")
  } else {
    println(message)
  }
}

///|
fn print_nuke_env_export() -> Unit {
  print_clear_moon_home_env_export()
}

///|
fn print_noop_env_export() -> Unit {
  println(":")
}

///|
fn print_clear_moon_home_env_export() -> Unit {
  println("unset MOON_HOME")
  println("_moonbee_home=\"${MOONBEE_HOME:-$HOME/.moonbee}\"")
  println("_moonbee_new_path=\"\"")
  println("_moonbee_rest=\"$PATH\"")
  println("while [ -n \"$_moonbee_rest\" ]; do")
  println("  case \"$_moonbee_rest\" in")
  println("    *:*)")
  println("      _moonbee_p=\"${_moonbee_rest%%:*}\"")
  println("      _moonbee_rest=\"${_moonbee_rest#*:}\"")
  println("      ;;")
  println("    *)")
  println("      _moonbee_p=\"$_moonbee_rest\"")
  println("      _moonbee_rest=\"\"")
  println("      ;;")
  println("  esac")
  println("  if [ -z \"$_moonbee_p\" ]; then")
  println("    continue")
  println("  fi")
  println("  case \"$_moonbee_p\" in")
  println("    \"$_moonbee_home/bin\"|\"$_moonbee_home/toolchains/\"*/bin)")
  println("      continue")
  println("      ;;")
  println("  esac")
  println("  if [ -z \"$_moonbee_new_path\" ]; then")
  println("    _moonbee_new_path=\"$_moonbee_p\"")
  println("  else")
  println("    _moonbee_new_path=\"${_moonbee_new_path}:$_moonbee_p\"")
  println("  fi")
  println("done")
  println("if [ -z \"$_moonbee_new_path\" ]; then")
  println(
    "  _moonbee_new_path=\"/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\"",
  )
  println("fi")
  println("export PATH=\"$_moonbee_new_path\"")
  println("hash -r 2>/dev/null || true")
  println("rehash 2>/dev/null || true")
  println("unset _moonbee_home _moonbee_new_path _moonbee_rest _moonbee_p")
}

///|
fn strip_shell_integration_blocks(content : String) -> (String, Int) {
  let mut current = content
  let mut removed = 0
  let start = shell_marker_start()
  let end = shell_marker_end()

  while current.contains(start) && current.contains(end) {
    let split_start = current.split_once(start)
    let (before, tail) = match split_start {
      Some((a, b)) => (a.to_string(), b.to_string())
      None => break
    }
    let split_end = tail.split_once(end)
    let after = match split_end {
      Some((_block, b)) => b.to_string()
      None => break
    }
    current = before + after
    removed = removed + 1
  }

  (current, removed)
}

///|
fn remove_shell_integration_from_file(path : String) -> Bool {
  let current = match read_text(path) {
    Some(v) => v
    None => return false
  }

  let (next, removed_count) = strip_shell_integration_blocks(current)
  if removed_count <= 0 {
    return false
  }

  write_text(path, next)
  true
}

///|
fn detect_shell_rc_file() -> String? {
  let shell = @sys.get_env_var("SHELL").unwrap_or("")
  if shell.has_suffix("/zsh") || shell == "zsh" {
    return Some(path_join(home_dir(), ".zshrc"))
  }
  if shell.has_suffix("/bash") || shell == "bash" {
    return Some(path_join(home_dir(), ".bashrc"))
  }
  None
}

///|
fn shell_marker_start() -> String {
  "# >>> moonbee initialize >>>"
}

///|
fn shell_marker_end() -> String {
  "# <<< moonbee initialize <<<"
}

///|
fn shell_integration_block() -> String {
  let body =
    #|# Added by moonbee.
    #|# Purpose: make `moonbee <target>` apply MOON_HOME/PATH in the current shell.
    #|# moonbee-shell-v2
    #|# To remove: delete this marker block, or run `moonbee nuke`.
    #|moonbee() {
    #|  case "$1" in
    #|    ""|help|--help|-h|init|install|uninstall|list)
    #|      command moonbee "$@"
    #|      ;;
    #|    use|nuke)
    #|      local __moonbee_env
    #|      __moonbee_env="$(command moonbee "$1" --emit-env "${@:2}")" || return $?
    #|      eval "$__moonbee_env"
    #|      ;;
    #|    *)
    #|      local __target="$1"
    #|      shift
    #|      local __moonbee_env
    #|      __moonbee_env="$(command moonbee "$__target" --emit-env "$@")" || return $?
    #|      eval "$__moonbee_env"
    #|      ;;
    #|  esac
    #|}
    #|

  shell_marker_start() + "\n" + body + shell_marker_end() + "\n"
}

///|
fn print_env_export(snapshot_path : String) -> Unit {
  let snapshot_bin = path_join(snapshot_path, "bin")
  let shared_bin = shared_bin_dir()
  println("export MOON_HOME=\"\{snapshot_path}\"")
  println("export PATH=\"\{snapshot_bin}:\{shared_bin}:$PATH\"")
  println("hash -r 2>/dev/null || true")
  println("rehash 2>/dev/null || true")
}

///|
fn home_dir() -> String {
  match @sys.get_env_var("HOME") {
    Some(v) => v
    None => {
      println("error: HOME is not set")
      @sys.exit(1)
      ""
    }
  }
}

///|
fn moonbee_home() -> String {
  match @sys.get_env_var("MOONBEE_HOME") {
    Some(v) => {
      let trimmed = v.trim().to_string()
      if trimmed == "" {
        path_join(home_dir(), ".moonbee")
      } else {
        trimmed
      }
    }
    None => path_join(home_dir(), ".moonbee")
  }
}

///|
fn shared_bin_dir() -> String {
  path_join(moonbee_home(), "bin")
}

///|
fn toolchains_dir() -> String {
  path_join(moonbee_home(), "toolchains")
}

///|
fn channels_dir() -> String {
  path_join(moonbee_home(), "channels")
}

///|
fn tmp_dir() -> String {
  path_join(moonbee_home(), "tmp")
}

///|
fn first_run_marker_file() -> String {
  path_join(moonbee_home(), ".first-run-done")
}

///|
fn snapshot_dir(version_id : String) -> String {
  path_join(toolchains_dir(), version_id)
}

///|
fn snapshot_bin_dir(snapshot_path : String) -> String {
  path_join(snapshot_path, "bin")
}

///|
fn snapshot_meta_file(snapshot_path : String) -> String {
  path_join(snapshot_path, "moonbee.meta")
}

///|
fn snapshot_bin_baseline_file(snapshot_path : String) -> String {
  path_join(snapshot_path, "moonbee.bin-baseline")
}

///|
fn channel_pointer_file(channel_name : String) -> String {
  path_join(channels_dir(), channel_name)
}

///|
fn path_join(base : String, child : String) -> String {
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

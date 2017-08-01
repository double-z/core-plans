###
# INSTALL_NODE_MODULES

_setup_node_vars() {
  # The default Node package if one cannot be detected
  _default_node_pkg="core/node"
  _jq="$(pkg_path_for jq-static)/bin/jq"

  # `$scaffolding_pkg_manager` is empty by default
  : "${scaffolding_node_pkg_manager:=}"
  # `$scaffolding_node_pkg` is empty by default
  : "${scaffolding_node_pkg:=}"

}

_detect_node() {
  if [[ -f "package.json" ]]; then
    # shellcheck disable=SC2002
    build_line "detected package.json in root directory. enabling Node.js support"
    if ! cat package.json | "$_jq" . > /dev/null; then
      exit_with "Failed to parse package.json as JSON." 6
    else
      _uses_node=true
      _cache_dirs="$(_get_node_cache_directories ${PLAN_CONTEXT})"
    fi
  else
    build_line \
      "Node Scaffolding did not find package.json in the root directory." 5
  fi
}

_detect_node_pkg_manager() {
  if [[ -n "${_uses_node:-}" ]]; then
    if [[ -n "$scaffolding_node_pkg_manager" ]]; then
      case "$scaffolding_node_pkg_manager" in
        npm)
          _node_pkg_manager=npm
          build_line "Detected package manager in Plan, using '$_node_pkg_manager'"
          ;;
        yarn)
          _node_pkg_manager=yarn
          build_line "Detected package manager in Plan, using '$_node_pkg_manager'"
          ;;
        *)
          local e
          e="Variable 'scaffolding_node_pkg_manager' can only be"
          e="$e set to: 'npm', 'yarn', or empty."
          exit_with "$e" 9
          ;;
      esac
    elif [[ -f yarn.lock ]]; then
      _node_pkg_manager=yarn
      build_line "Detected yarn.lock in root directory, using '$_node_pkg_manager'"
    else
      _node_pkg_manager=npm
      build_line "No package manager could be detected, using default '$_node_pkg_manager'"
    fi
  fi
}

_update_node_vars() {
  if [[ -n "${_uses_node:-}" ]]; then
    _set_if_unset scaffolding_env NODE_MODULES_PREBUILD "{{cfg.node_modules_prebuild}}"
    _set_if_unset scaffolding_env NODE_ENV "{{cfg.node_env}}"
    _set_if_unset scaffolding_env NODE_MODULES_CACHE "{{cfg.node_modules_cache}}"
  fi
}

_detect_yarn() {
  build_line "Running scaffolding_node_modules_install"
  if [[ -n "$_uses_node" ]]; then
    # Support custom version of Yarn package
    if [[ "$_node_pkg_manager" == "yarn" ]]; then
      build_line "Adding Yarn package to build dependencies"
      local val
      val="$(_json_val package.json .engines.yarn)"
      if [[ -n "$val" ]]; then
        # TODO fin: Add more robust packages.json to Habitat package matching
        case "$val" in
          *)
            _yarn_pkg="core/yarn/$val"
            ;;
        esac
        build_line "Detected Yarn version '$val' in package.json, using '$_yarn_pkg'"
      else
        _yarn_pkg="core/yarn"
        build_line "No Yarn version detected in package.json, using default '$_yarn_pkg'"
      fi
      pkg_build_deps=($_yarn_pkg ${pkg_build_deps[@]})
      debug "Updating pkg_build_deps=(${pkg_build_deps[*]}) from Scaffolding detection"
    else
      build_line "Yarn not detected as package manager"
    fi
  fi
}

_detect_node_pkg() {
  build_line "Running _detect_node_pkg"
  if [[ -n "${_uses_node:-}" ]]; then
    if   [[ -n "$scaffolding_node_pkg" ]]; then
      _node_pkg="$scaffolding_node_pkg"
      build_line "Detected Node.js version in Plan, using '$_node_pkg'"
    else
      local val
      val="$(_json_val package.json .engines.node)"
      if [[ -n "$val" ]]; then
        # TODO fin: Add more robust packages.json to Habitat package matching
        case "$val" in
          *)
            _node_pkg="core/node/$val"
            ;;
        esac
        build_line "Detected Node.js version '$val' in package.json, using '$_node_pkg'"
      elif [[ -f .nvmrc && -n "$(cat .nvmrc)" ]]; then
        val="$(trim "$(cat .nvmrc)")"
        # TODO fin: Add more robust .nvmrc to Habitat package matching
        case "$val" in
          *)
            _node_pkg="core/node/$val"
            ;;
        esac
        build_line "Detected Node.js version '$val' in .nvmrc, using '$_node_pkg'"
      else
        _node_pkg="$_default_node_pkg"
        build_line "No Node.js version detected in Plan, package.json, or .nvmrc, using default '$_node_pkg'"
      fi
    fi
    pkg_deps=($_node_pkg ${pkg_deps[@]})
    debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"

  elif _has_gem execjs; then
    build_line "Detected 'execjs' gem in Gemfile.lock, adding node packages"
    pkg_deps=($_default_node_pkg ${pkg_deps[@]})
    debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
  fi
}

# Runs npm/yarn install commands
scaffolding_node_modules_install() {
  build_line "Running scaffolding_node_modules_install"
  if [[ -n "${_uses_node:-}" ]]; then

    if [[ -n "${_uses_git:-}" ]]; then
      if ! git check-ignore node_modules && [[ -d node_modules ]]; then
        warn "Detected directory 'node_modules' is not in .gitignore and is"
        warn "not empty."
        warn "It is not recommended to commit your node modules into your"
        warn "codebase."
        warn "We will continue assuming a 'NODE_MODULES_PREBUILD' and rebuild the existing modules"
        warn "To disable using all modules set 'NODE_MODULES_CACHE=false'"
        warn "To disable using the existing local modules add 'node_modules' to .gitignore"

        build_line "Prebuild detected (node_modules already exists)"
        _restore_node_cache_directories "$(pwd)" "$CACHE_PATH" "$_cache_dirs"
        NODE_MODULES_PREBUILD=true
      fi
    fi

    build_line "Installing dependencies using $_node_pkg_manager $("$_node_pkg_manager" --version)"
    start_sec="$SECONDS"
    case "$_node_pkg_manager" in
      npm)
        build_line "CACHE_DIRS:$_cache_dirs"
        if [[ -n "${_cache_dirs:-}" ]]; then
          build_line "Found Cache Dirs: $_cache_dirs"
          for cache_dir in ${_cache_dirs[@]}; do
            build_line "Ensuring $CACHE_PATH/$cache_dir exists..."
            # Guard against the unlikey but possible i.e "client/node_modules/"
            trim_trailing_slash=${cache_dir%/}
            # Deduct package.json path from corresponding node_modules path
            package_json_path="$(echo $trim_trailing_slash | sed 's/node_modules/package.json/g')"
            build_line "PKG_JSON_PATH is $package_json_path"


            if [[ ! -f "$CACHE_PATH/$package_json_path" \
                  && -f "$package_json_path" ]]; then
              [[ -d $CACHE_PATH/$cache_dir ]] || mkdir -p $CACHE_PATH/$cache_dir
              build_line "Copying $package_json_path to $CACHE_PATH/$package_json_path"
              cp -rfv "$package_json_path" "$CACHE_PATH/$package_json_path"
            fi
            attach

          done
        else
          build_line 'No _cache_dirs found'
        fi
        if [[ -f "npm-shrinkwrap.json" ]]; then
          cp -av npm-shrinkwrap.json "$CACHE_PATH/"
        fi
        if [[ -n "$HAB_NONINTERACTIVE" ]]; then
          export NPM_CONFIG_PROGRESS=false
        fi
        pushd "$CACHE_PATH" > /dev/null
          if [[ "$NODE_MODULES_PREBUILD" == "true" ]]; then
            build_line "Rebuilding any native modules"
            npm rebuild
          else
            build_line "Pruning any extraneous node modules"
            npm prune \
              --unsafe-perm \
              --userconfig "$CACHE_PATH/.npmrc"
          fi

          if [[ -e "$CACHE_PATH/npm-shrinkwrap.json" ]]; then
            build_line "Installing any new modules (package.json + shrinkwrap)"
          else
            build_line "Installing any new modules (package.json)"
          fi

          npm install \
            --unsafe-perm \
            --production \
            --loglevel error \
            --fetch-retries 5 \
            --userconfig "$CACHE_PATH/.npmrc"
          npm list --json > npm-list.json
        popd > /dev/null
        ;;
      yarn)
        local extra_args
        if [[ -n "$HAB_NONINTERACTIVE" ]]; then
          extra_args="--no-progress"
        fi
        yarn install $extra_args \
          --pure-lockfile \
          --ignore-engines \
          --production \
          --modules-folder "$CACHE_PATH/node_modules" \
          --cache-folder "$CACHE_PATH/yarn_cache"
        ;;
      *)
        local e
        e="Internal error: package manager variable"
        e="$e not correctly set: '$_node_pkg_manager'"
        exit_with "$e" 9
        ;;
    esac
    elapsed=$((SECONDS - start_sec))
    elapsed=$(echo $elapsed | awk '{printf "%dm%ds", $1/60, $1%60}')
    build_line "Dependency installation completed ($elapsed)"
    return 0
  fi
}

# scaffolding_node_setup_config() {
scaffolding_node_setup_config() {
  build_line "Running scaffolding_node_setup_config"
  if [[ -n "${_uses_node:-}" ]]; then
    local t
    t="$CACHE_PATH/default.scaffolding.toml"

    echo "" >> "$t"

    if _default_toml_has_no node_modules_prebuild \
        && [[ -v "scaffolding_env[NODE_MODULES_PREBUILD]" ]]; then
      echo 'Setting `node_modules_prebuild = "true"` by default\n' >> "$t"
      echo 'This will force an `npm rebuild` if `node_modules` exists and is not in .gitignore\n' >> "$t"
      echo 'Set this to `false` or add `node_modules` to your `.gitignore` to disable this behavior\n' >> "$t"
      echo 'node_modules_prebuild = "true"' >> "$t"
    fi
    if _default_toml_has_no node_env \
        && [[ -v "scaffolding_env[NODE_ENV]" ]]; then
      echo 'node_env = "production"' >> "$t"
    fi
    if _default_toml_has_no node_modules_cache \
        && [[ -v "scaffolding_env[NODE_MODULES_CACHE]" ]]; then
      echo 'node_modules_cache = "true"' >> "$t"
    fi
  fi
}

scaffolding_node_install_modules() {
  build_line "Running scaffolding_node_install_modules"
  local cache_status cache_directories
  if [[ -n "${_uses_node:-}" ]]; then
    cache_status=$(_get_node_cache_status)
    if [ "$cache_status" == "disabled" ]; then
      build_line "Skipping (cache disabled)"
    else
      cache_directories=$(_get_node_cache_directories)
      if [ "$cache_directories" == "" ]; then
        build_line "Loading 1 from cacheDirectories (default):"
        _restore_node_cache_directories $CACHE_PATH $scaffolding_app_prefix "node_modules"
      else
        build_line "Loading $(echo $cache_directories | wc -w | xargs) from cacheDirectories (package.json):"
        _restore_node_cache_directories $CACHE_PATH $scaffolding_app_prefix $cache_directories
      fi
    fi

    if [[ -n "$_cache_dirs" ]]; then
      for cache_dir in ${_cache_dirs[@]}; do
        if [[ -f "$CACHE_PATH/$cache_dir/../package.json" \
            && ! -f "$scaffolding_app_prefix/$cache_dir/../package.json" ]]; then
          [[ -d $scaffolding_app_prefix/$cache_dir ]] || mkdir -p $scaffolding_app_prefix/$cache_dir
          build_line "copying $CACHE_PATH/$cache_dir/../package.json to $scaffolding_app_prefix/$cache_dir/../."
          cp -rf "$CACHE_PATH/$cache_dir/../package.json" "$scaffolding_app_prefix/$cache_dir/../."
        fi
      done
    fi

    if [[ -f "$CACHE_PATH/npm-list.json" \
        && ! -f "$scaffolding_app_prefix/npm-list.json" ]]; then
      cp -av "$CACHE_PATH/npm-list.json" "$scaffolding_app_prefix/"
    fi
  fi
}

scaffolding_node_fix_shebangs() {
  local shebang bin_path
  if [[ -n "${_uses_node:-}" ]]; then
    shebang="#!$(pkg_path_for "$_node_pkg")/bin/node"
    if [[ -n "$_cache_dirs" ]]; then
      for cache_dir in "${_cache_dirs[@]}"; do
        bin_path=$(basename "$scaffolding_app_prefix")/$cache_dir/.bin
        if [[ -d "$bin_path" ]]; then
          build_line "Fixing Node shebang for node_module bins in $bin_path"
          find "$bin_path" -type f -o -type l | while read -r bin; do
            sed -e "s|^#!.\{0,\}\$|${shebang}|" -i "$(readlink -f "$bin")"
          done
        fi
      done
    fi
  fi
}

###
# Cache Handling - Move modules to $scaffolding_app_prefix

_get_node_cache_status() {
  if ! ${NODE_MODULES_CACHE:-true}; then
    echo "disabled"
  else
    echo "valid"
  fi
}

_get_node_cache_directories() {
  local pkg_json_path="/src"
  local dirs1=$(_json_val "$pkg_json_path/package.json" ".cacheDirectories | .[]?")
  local dirs2=$(_json_val "$pkg_json_path/package.json" ".cache_directories | .[]?")

  if [[ -n "${dirs1:-}" ]]; then
    echo "$dirs1"
  elif [[ -n "${dirs2:-}" ]]; then
    echo "$dirs2"
  else
    echo 
  fi
}

_restore_node_cache_directories() {
  local build_dir=$1
  local cache_dir=$2

  for cachepath in ${@:3}; do
    if [ -e "$cache_dir/$cachepath" ]; then
      build_line "- $cachepath (exists - skipping)"
    else
      if [ -e "$build_dir/$cachepath" ]; then
        build_line "- Installing vendored node modules to: $cache_dir/$cachepath"
        mkdir -p $(dirname "$cache_dir/$cachepath")
        cp -rf "$build_dir/$cachepath" "$cache_dir/$cachepath"
        if [[ -f "$build_dir/$cachepath/../package.json" ]]; then
          build_line "copying /../package.json to $cache_dir/$cachepath/../."
          cp -rf "$build_dir/$cachepath/../package.json" "$cache_dir/$cachepath/../."
        fi
      else
        build_line "- $build_dir/$cachepath (not cached - skipping)"
      fi
    fi
  done
}

# With thanks to:
# https://github.com/heroku/heroku-buildpack-nodejs/blob/master/lib/json.sh
# shellcheck disable=SC2002
_json_val() {
  local json
  json="$1"
  path="$2"

  cat "$json" | "$_jq" --raw-output "$path // \"\""
}
function dr-summary {
  # ANSI colour palette
  local RST='\033[0m'
  local BOLD='\033[1m'
  local DIM='\033[2m'

  local C_BORDER='\033[38;5;33m'      # blue
  local C_HEADER='\033[38;5;39m'      # bright blue
  local C_KEY='\033[38;5;250m'        # light grey
  local C_VAL='\033[38;5;222m'        # amber
  local C_OK='\033[38;5;82m'          # green
  local C_WARN='\033[38;5;220m'       # yellow
  local C_ERR='\033[38;5;196m'        # red
  local C_SECTION='\033[38;5;75m'     # sky blue

  # ── dynamic width / height ──────────────────────────────────────────────
  local TERM_W WIDE=false W
  TERM_W=$(tput cols 2>/dev/null || echo 80)
  TERM_H=$(tput lines 2>/dev/null || echo 24)
  _dr_lines=0   # running line counter (non-local so helpers can increment)
  if [[ $TERM_W -ge 120 ]]; then
    W=118   # total box width = W+2 = 120
    WIDE=true
  else
    W=$(( TERM_W - 2 ))
    [[ $W -lt 78 ]] && W=78
  fi
  # Two-column content widths: │ space WL space │ space WR space │ = WL+WR+7 = W+2
  local WL=$(( (W - 5) / 2 ))
  local WR=$(( W - 5 - WL ))

  # ── helpers ───────────────────────────────────────────────────────────────
  _dr_hline() {
    local L="$1" M="$2" R="$3"
    printf "${C_BORDER}${L}"; printf "${M}%.0s" $(seq 1 $W); printf "${R}${RST}\n"
    (( ++_dr_lines ))
  }
  _dr_row() {
    local text="$1"
    local plain; plain=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local pad=$(( W - ${#plain} - 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf "${C_BORDER}│${RST} %b%-*s ${C_BORDER}│${RST}\n" "$text" "$pad" ""
    (( ++_dr_lines ))
  }
  _dr_blank() { _dr_row ""; }
  _dr_section() {
    _dr_hline "├" "─" "┤"
    local label=" ${BOLD}${C_SECTION}$1${RST}"
    [[ -n "${2:-}" ]] && label+="${DIM}  $2${RST}"
    _dr_row "$label"
    _dr_hline "├" "─" "┤"
  }
  _dr_kv() {
    local k="$1" v="$2" s="${3:-}"
    local vc="$C_VAL"
    [[ "$s" == "ok"   ]] && vc="$C_OK"
    [[ "$s" == "warn" ]] && vc="$C_WARN"
    [[ "$s" == "err"  ]] && vc="$C_ERR"
    _dr_row " ${C_KEY}$(printf '%-22s' "$k")${RST} ${vc}${v}${RST}"
  }
  _dr_hline_2col() {  # L M1 SEP M2 R
    local L="$1" M1="$2" SEP="$3" M2="$4" R="$5"
    local LD=$(( WL + 2 )) RD=$(( WR + 2 ))
    printf "${C_BORDER}${L}"
    printf "${M1}%.0s" $(seq 1 $LD)
    printf "${SEP}"
    printf "${M2}%.0s" $(seq 1 $RD)
    printf "${R}${RST}\n"
    (( ++_dr_lines ))
  }
  _dr_row_2col() {
    local lt="$1" rt="${2:-}"
    local lp; lp=$(echo -e "$lt" | sed 's/\x1b\[[0-9;]*m//g')
    local rp; rp=$(echo -e "$rt" | sed 's/\x1b\[[0-9;]*m//g')
    local lpad=$(( WL - ${#lp} )) rpad=$(( WR - ${#rp} ))
    [[ $lpad -lt 0 ]] && lpad=0
    [[ $rpad -lt 0 ]] && rpad=0
    printf "${C_BORDER}│${RST} %b%-*s ${C_BORDER}│${RST} %b%-*s ${C_BORDER}│${RST}\n" \
      "$lt" "$lpad" "" "$rt" "$rpad" ""
    (( ++_dr_lines ))
  }

  # ── pre-compute git branch / update status ───────────────────────────────
  local _git_branch _git_update_available=false
  _git_branch=$(git -C "$DR_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  timeout 5 git -C "$DR_DIR" fetch --quiet origin 2>/dev/null || true
  local _local_hash _remote_hash
  _local_hash=$(git -C "$DR_DIR" rev-parse HEAD 2>/dev/null || true)
  _remote_hash=$(git -C "$DR_DIR" rev-parse '@{u}' 2>/dev/null || true)
  if [[ -n "$_local_hash" && -n "$_remote_hash" && "$_local_hash" != "$_remote_hash" ]]; then
    _git_update_available=true
  fi

  # ── pre-compute dynamic values ────────────────────────────────────────────
  local cloud_val="${DR_CLOUD:-n/a}"
  [[ "${DR_CLOUD,,}" == "aws" ]] && cloud_val="aws"
  [[ "${DR_CLOUD,,}" == "remote" ]] && cloud_val="remote"

  local s3_color
  if aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3api head-bucket \
      --bucket "${DR_LOCAL_S3_BUCKET}" >/dev/null 2>&1; then
    s3_color="${C_OK}"
  else
    s3_color="${C_ERR}"
  fi

  local nvidia_runtime
  if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    nvidia_runtime="${C_OK}available${RST}"
  else
    nvidia_runtime="${C_WARN}not found${RST}"
  fi

  # ── header ────────────────────────────────────────────────────────────────
  echo; (( ++_dr_lines ))
  _dr_hline "╭" "─" "╮"
  _dr_row " ${BOLD}${C_HEADER}DeepRacer for Cloud  —  Environment Summary${RST}"
  _dr_row " ${DIM}Config: ${DR_CONFIG}${RST}"
  local _branch_row=" ${DIM}Branch: ${RST}${C_VAL}${_git_branch:-unknown}${RST}"
  if [[ "$_git_update_available" == true ]]; then
    _branch_row+="  ${C_WARN}⬆ update available — run 'git pull'${RST}"
  fi
  _dr_row "$_branch_row"

  # ── system config + run config ────────────────────────────────────────────
  if [[ "$WIDE" == true ]]; then
    local CKW=18  # key column width in 2-col mode
    _dr_hline_2col "├" "─" "┬" "─" "┤"
    _dr_row_2col \
      " ${BOLD}${C_SECTION}System Configuration${RST}" \
      " ${BOLD}${C_SECTION}Run Configuration${RST}${DIM}  ID: ${DR_RUN_ID:-0}${RST}"
    _dr_hline_2col "├" "─" "┼" "─" "┤"

    local lrows=() rrows=()
    lrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'Docker style')${RST} ${C_VAL}${DR_DOCKER_STYLE:-swarm}${RST}")
    lrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'Cloud / Bucket')${RST} ${DIM}${cloud_val}${RST}  ${s3_color}${DR_LOCAL_S3_BUCKET:-n/a}${RST}")
    lrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'Workers')${RST} ${C_VAL}${DR_WORKERS:-1}${RST}")
    lrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'NVIDIA runtime')${RST} ${nvidia_runtime}")

    rrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'Model prefix')${RST} ${C_VAL}${DR_LOCAL_S3_MODEL_PREFIX:-n/a}${RST}")
    rrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'Race type')${RST} ${C_VAL}${DR_RACE_TYPE:-n/a}${RST}")
    rrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'World / track')${RST} ${C_VAL}${DR_WORLD_NAME:-n/a}${RST}")
    rrows+=(" ${C_KEY}$(printf '%-*s' $CKW 'Car name')${RST} ${C_VAL}${DR_CAR_NAME:-n/a}${RST}")

    local max_r=$(( ${#lrows[@]} > ${#rrows[@]} ? ${#lrows[@]} : ${#rrows[@]} ))
    for (( i=0; i<max_r; i++ )); do
      _dr_row_2col "${lrows[$i]:-}" "${rrows[$i]:-}"
    done
    _dr_hline_2col "├" "─" "┴" "─" "┤"
  else
    _dr_section "System Configuration"
    _dr_row " ${C_KEY}$(printf '%-22s' 'Docker style')${RST} ${C_VAL}${DR_DOCKER_STYLE:-swarm}${RST}"
    _dr_row " ${C_KEY}$(printf '%-22s' 'Cloud / Bucket')${RST} ${DIM}${cloud_val}${RST}  ${s3_color}${DR_LOCAL_S3_BUCKET:-n/a}${RST}"
    _dr_kv "Workers"        "${DR_WORKERS:-1}"
    _dr_row " ${C_KEY}$(printf '%-22s' 'NVIDIA runtime')${RST} ${nvidia_runtime}"
    _dr_section "Run Configuration" "ID: ${DR_RUN_ID:-0}"
    _dr_kv "Model prefix"   "${DR_LOCAL_S3_MODEL_PREFIX:-n/a}"
    _dr_kv "Race type"      "${DR_RACE_TYPE:-n/a}"
    _dr_kv "World / track"  "${DR_WORLD_NAME:-n/a}"
    _dr_kv "Car name"       "${DR_CAR_NAME:-n/a}"
  fi

  # ── simapp version check (used inline in docker images section) ───────────
  local simapp_update_available=false _required_simapp_ver=""
  _required_simapp_ver=$(jq -r '.containers.simapp | select (.!=null)' "$DR_DIR/defaults/dependencies.json" 2>/dev/null || true)
  if [[ -n "$_required_simapp_ver" && -n "${DR_SIMAPP_VERSION:-}" ]]; then
    local _configured_simapp_ver
    _configured_simapp_ver=$(echo "${DR_SIMAPP_VERSION}" | grep -oP '^\d+\.\d+(\.\d+)?')
    if [[ -n "$_configured_simapp_ver" ]] && ! verlte "$_required_simapp_ver" "$_configured_simapp_ver"; then
      simapp_update_available=true
    fi
  fi

  # ── docker images ─────────────────────────────────────────────────────────
  if [[ "$WIDE" == true ]]; then
    # 2-col closing line already drawn; just add section label row
    local label=" ${BOLD}${C_SECTION}Configured Docker Images${RST}"
    _dr_row "$label"
    _dr_hline "├" "─" "┤"
  else
    _dr_section "Configured Docker Images"
  fi

  local simapp_img="${DR_SIMAPP_SOURCE}:${DR_SIMAPP_VERSION}"
  local simapp_disp="${simapp_img/awsdeepracercommunity/[a-d-c]}"
  local simapp_id; simapp_id=$(docker image inspect "$simapp_img" --format '{{slice .Id 7 19}}' 2>/dev/null)

  local analysis_img="awsdeepracercommunity/deepracer-analysis:${DR_ANALYSIS_IMAGE:-cpu}"
  local analysis_disp="${analysis_img/awsdeepracercommunity/[a-d-c]}"
  local analysis_id; analysis_id=$(docker image inspect "$analysis_img" --format '{{slice .Id 7 19}}' 2>/dev/null)

  local minio_img="" minio_disp="" minio_id=""
  if [[ "${DR_CLOUD,,}" == "local" || "${DR_CLOUD,,}" == "azure" ]]; then
    minio_img="minio/minio:${DR_MINIO_IMAGE:-latest}"
    minio_disp="$minio_img"
    minio_id=$(docker image inspect "$minio_img" --format '{{slice .Id 7 19}}' 2>/dev/null)
    if [[ -z "$minio_id" ]]; then
      minio_id=$(docker images minio/minio --format '{{slice .ID 0 12}}' 2>/dev/null | head -1)
    fi
  fi

  local _simapp_upd_note=""
  [[ "$simapp_update_available" == true ]] && _simapp_upd_note="  ${C_WARN}⬆ update available (→ ${_required_simapp_ver})${RST}"

  if [[ "$WIDE" == true ]]; then
    local IKW=14
    if [[ -n "$simapp_id" ]]; then
      _dr_row " ${C_KEY}$(printf '%-*s' $IKW 'SimApp')${RST} ${C_OK}${simapp_disp}${RST}  ${DIM}ID: ${simapp_id}  ✓ local${RST}${_simapp_upd_note}"
    else
      _dr_row " ${C_KEY}$(printf '%-*s' $IKW 'SimApp')${RST} ${C_WARN}${simapp_disp}  (not pulled)${RST}${_simapp_upd_note}"
    fi
    if [[ -n "$analysis_id" ]]; then
      _dr_row " ${C_KEY}$(printf '%-*s' $IKW 'Analysis')${RST} ${C_OK}${analysis_disp}${RST}  ${DIM}ID: ${analysis_id}  ✓ local${RST}"
    else
      _dr_row " ${C_KEY}$(printf '%-*s' $IKW 'Analysis')${RST} ${C_WARN}${analysis_disp}  (not pulled)${RST}"
    fi
    if [[ -n "$minio_img" ]]; then
      if [[ -n "$minio_id" ]]; then
        _dr_row " ${C_KEY}$(printf '%-*s' $IKW 'MinIO')${RST} ${C_OK}${minio_disp}${RST}  ${DIM}ID: ${minio_id}  ✓ local${RST}"
      else
        _dr_row " ${C_KEY}$(printf '%-*s' $IKW 'MinIO')${RST} ${C_WARN}${minio_disp}  (not pulled)${RST}"
      fi
    fi
  else
    if [[ -n "$simapp_id" ]]; then
      _dr_kv "SimApp" "${simapp_disp}" "ok"
      _dr_row " ${DIM}$(printf '%22s' '') ID: ${simapp_id}  ✓ local${RST}${_simapp_upd_note}"
    else
      _dr_kv "SimApp" "${simapp_disp}  (not pulled)${_simapp_upd_note}" "warn"
    fi
    if [[ -n "$analysis_id" ]]; then
      _dr_kv "Analysis" "${analysis_disp}" "ok"
      _dr_row " ${DIM}$(printf '%22s' '') ID: ${analysis_id}  ✓ local${RST}"
    else
      _dr_kv "Analysis" "${analysis_disp}  (not pulled)" "warn"
    fi
    if [[ -n "$minio_img" ]]; then
      if [[ -n "$minio_id" ]]; then
        _dr_kv "MinIO" "${minio_disp}" "ok"
        _dr_row " ${DIM}$(printf '%22s' '') ID: ${minio_id}  ✓ local${RST}"
      else
        _dr_kv "MinIO" "${minio_disp}  (not pulled)" "warn"
      fi
    fi
  fi

  # ── services and containers ───────────────────────────────────────────────
  _dr_section "DeepRacer Services And Containers"
  local found_any=false

  if [[ "${DR_DOCKER_STYLE,,}" == "swarm" ]]; then
    local stack_lines
    stack_lines=$(docker stack ls --format '{{.Name}}\t{{.Services}}' 2>/dev/null || true)
    if [[ -n "$stack_lines" ]]; then
      found_any=true
      _dr_row " ${DIM}Swarm stacks:${RST}"
      while IFS=$'\t' read -r stname stsvcs; do
        _dr_row " ${C_KEY}$(printf '%-30s' "$stname")${RST} ${C_VAL}${stsvcs} service(s)${RST}"
      done <<< "$stack_lines"
    fi

    local svc_lines
    svc_lines=$(docker service ls --format '{{.Name}}\t{{.Replicas}}\t{{.Image}}' 2>/dev/null \
      | grep -i '^deepracer' || true)
    if [[ -n "$svc_lines" ]]; then
      found_any=true
      _dr_row " ${DIM}Swarm services:${RST}"
      while IFS=$'\t' read -r sname sreplicas simage; do
        local desired actual
        desired=$(echo "$sreplicas" | cut -d'/' -f2)
        actual=$(echo "$sreplicas" | cut -d'/' -f1)
        local rep_color="$C_OK"
        [[ "$actual" != "$desired" ]] && rep_color="$C_WARN"
        local simage_disp="${simage/awsdeepracercommunity/[a-d-c]}"
        _dr_row " ${C_KEY}$(printf '%-30s' "$sname")${RST} ${rep_color}$(printf '%-8s' "$sreplicas")${RST} ${DIM}${simage_disp}${RST}"
      done <<< "$svc_lines"
    fi

    local container_lines
    container_lines=$(docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null \
      | while IFS=$'\t' read -r cn cs ci; do
          if echo "$cn" | grep -qiE '^deepracer|robomaker|sagemaker|minio|rl_coach|analysis' \
             || [[ "$ci" == "$simapp_img"* ]]; then
            printf '%s\t%s\n' "$cn" "$cs"
          fi
        done)
    if [[ -n "$container_lines" ]]; then
      found_any=true
      local n_ctrs; n_ctrs=$(echo "$container_lines" | wc -l)
      _dr_row " ${DIM}Containers:${RST}"
      # 3 lines reserved for footer (blank row + closing hline + trailing newline)
      if (( _dr_lines + n_ctrs + 3 > TERM_H )); then
        _dr_row "   ${DIM}${n_ctrs} container(s) running  ${C_WARN}(terminal too short to list)${RST}"
      else
        while IFS=$'\t' read -r cname cstatus; do
          local status_color="$C_OK"
          [[ "$cstatus" != Up* ]] && status_color="$C_WARN"
          _dr_row " ${C_KEY}$(printf '%-30s' "$cname")${RST} ${status_color}${cstatus}${RST}"
        done <<< "$container_lines"
      fi
    fi
  else
    local proj_lines
    proj_lines=$(docker compose ls --format json 2>/dev/null \
      | jq -r '.[] | select(.Name | test("deepracer|s3"; "i")) | "\(.Name)\t\(.Status)"' 2>/dev/null || true)
    if [[ -n "$proj_lines" ]]; then
      found_any=true
      _dr_row " ${DIM}Compose projects:${RST}"
      while IFS=$'\t' read -r pname pstatus; do
        local pstatus_color="$C_OK"
        [[ "$pstatus" != *running* ]] && pstatus_color="$C_WARN"
        _dr_row " ${C_KEY}$(printf '%-30s' "$pname")${RST} ${pstatus_color}${pstatus}${RST}"
      done <<< "$proj_lines"
    fi

    local container_lines
    container_lines=$(docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null \
      | while IFS=$'\t' read -r cn cs ci; do
          if echo "$cn" | grep -qiE '^deepracer|robomaker|sagemaker|minio|rl_coach|analysis' \
             || [[ "$ci" == "$simapp_img"* ]]; then
            printf '%s\t%s\n' "$cn" "$cs"
          fi
        done)
    if [[ -n "$container_lines" ]]; then
      found_any=true
      local n_ctrs; n_ctrs=$(echo "$container_lines" | wc -l)
      _dr_row " ${DIM}Compose services:${RST}"
      if (( _dr_lines + n_ctrs + 3 > TERM_H )); then
        _dr_row "   ${DIM}${n_ctrs} container(s) running  ${C_WARN}(terminal too short to list)${RST}"
      else
        while IFS=$'\t' read -r cname cstatus; do
          local status_color="$C_OK"
          [[ "$cstatus" != Up* ]] && status_color="$C_WARN"
          _dr_row " ${C_KEY}$(printf '%-30s' "$cname")${RST} ${status_color}${cstatus}${RST}"
        done <<< "$container_lines"
      fi
    fi
  fi

  if [[ "$found_any" == false ]]; then
    _dr_row "  ${C_WARN}No DeepRacer-related services or containers running.${RST}"
  fi

  # ── footer ────────────────────────────────────────────────────────────────
  _dr_blank
  _dr_hline "╰" "─" "╯"
  echo
}

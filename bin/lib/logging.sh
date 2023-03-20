
# Logging functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

function set_log_level() {
    # Check if the environment file exists
    log_message debug "Setting log level"
    if [[ -f "$1" ]]; then
        # Read the file line by line
        log_message debug "Environment file found, starting to parse"
        while read line; do
            # Ignore comment lines and empty lines
            if [[ ! "$line" =~ ^\s*# && "$line" != "" ]]; then
                # Extract the variable name and value
                varname=$(echo "$line" | cut -d= -f1)
                if [[ "$varname" == "DR_LOGGER_LEVEL" ]]; then
                    log_message debug "Found DR_LOGGER_LEVEL variable"
                    value=$(echo "$line" | cut -d= -f2-)
                    log_message debug "Value of DR_LOGGER_LEVEL is ${value^^}"
                    # Set the environment variable
                    export "$varname"="$value"
                    log_message debug "DR_LOGGER_LEVEL exported"
                fi
            fi
        done < "$1"
        # Set the log level based on the DR_LOGGER_LEVEL variable
        case $DR_LOGGER_LEVEL in
          ERROR)
            LOG_LEVEL=0
            ;;
          WARNING)
            LOG_LEVEL=1
            ;;
          INFO)
            LOG_LEVEL=2
            ;;
          DEBUG)
            LOG_LEVEL=3
            ;;
          *)
            echo "Invalid log level, or variable not found, defaulting to INFO"
            LOG_LEVEL=2
            ;;
        esac
        export LOG_LEVEL
        log_message info "Log level set to ${log_level^^}"
    else
        log_message warning "Environment file not found, defaulting to INFO"
        LOG_LEVEL=2
        export LOG_LEVEL
    fi
}


function log_message() {
    local level=$1
    local message=$2
    local log_level=$LOG_LEVEL
    local date="$(date +"%Y-%m-%d %H:%M:%S")"
    local color=
    case $level in
        error)
            if [ "$log_level" -ge "$ERROR" ]; then
                color="\033[1;31m"  # Bold red
                echo -e "${color}[ERROR] $date: $message\033[0m"
            fi
            ;;
        warning)
            if [ "$log_level" -ge "$WARNING" ]; then
                color="\033[1;33m"  # Bold yellow
                echo -e "${color}[WARNING] $date: $message\033[0m"
            fi
            ;;
        info)
            if [ "$log_level" -ge "$INFO" ]; then
                color="\033[1;32m"  # Bold green
                echo -e "${color}[INFO] $date: $message\033[0m"
            fi
            ;;
        debug)
            if [ "$log_level" -ge "$DEBUG" ]; then
                color="\033[1;34m"  # Bold blue
                echo -e "${color}[DEBUG] $date: $message\033[0m"
            fi
            ;;
        *)
            echo "Invalid log level: $level"
            ;;
    esac
}

cli_log_level() {
  # Set log level based on command-line argument

  if [ -z "$1" ]; then
    return
  fi

  case $1 in
    error)
      export LOG_LEVEL=$ERROR
      ;;
    warning)
      export LOG_LEVEL=$WARNING
      ;;
    info)
      export LOG_LEVEL=$INFO
      ;;
    debug)
      export LOG_LEVEL=$DEBUG
      ;;
    *)
      echo "Invalid log level: $1"
      exit 1
      ;;
  esac
}


# Logging functions
#-----------------------------------------------------------------------------------------------------------------------
# LOG_LEVEL needs to be defined in the importing script

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

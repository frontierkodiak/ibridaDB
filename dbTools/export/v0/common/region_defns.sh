#!/bin/bash
# ------------------------------------------------------------------------------
# region_defns.sh
# ------------------------------------------------------------------------------
# This file defines the bounding box coordinates for each supported region.
#
# Usage:
#   source region_defns.sh
#   Then set REGION_TAG in your environment, and use get_region_coordinates()
#   to populate XMIN, XMAX, YMIN, YMAX environment variables.
# ------------------------------------------------------------------------------

declare -A REGION_COORDINATES

# North America
REGION_COORDINATES["NAfull"]="(-169.453125 12.211180 -23.554688 84.897147)"

# Europe
REGION_COORDINATES["EURwest"]="(-12.128906 40.245992 12.480469 60.586967)"
REGION_COORDINATES["EURnorth"]="(-25.927734 54.673831 45.966797 71.357067)"
REGION_COORDINATES["EUReast"]="(10.722656 41.771312 39.550781 59.977005)"
REGION_COORDINATES["EURfull"]="(-30.761719 33.284620 43.593750 72.262310)"

# Mediterranean
REGION_COORDINATES["MED"]="(-16.259766 29.916852 36.474609 46.316584)"

# Australia
REGION_COORDINATES["AUSfull"]="(111.269531 -47.989922 181.230469 -9.622414)"

# Asia
REGION_COORDINATES["ASIAse"]="(82.441406 -11.523088 153.457031 28.613459)"
REGION_COORDINATES["ASIAeast"]="(462.304688 23.241346 550.195313 78.630006)"
REGION_COORDINATES["ASIAcentral"]="(408.515625 36.031332 467.753906 76.142958)"
REGION_COORDINATES["ASIAsouth"]="(420.468750 1.581830 455.097656 39.232253)"
REGION_COORDINATES["ASIAsw"]="(386.718750 12.897489 423.281250 48.922499)"
REGION_COORDINATES["ASIA_nw"]="(393.046875 46.800059 473.203125 81.621352)"

# South America
REGION_COORDINATES["SAfull"]="(271.230469 -57.040730 330.644531 15.114553)"

# Africa
REGION_COORDINATES["AFRfull"]="(339.082031 -37.718590 421.699219 39.232253)"

# ------------------------------------------------------------------------------
# get_region_coordinates()
# ------------------------------------------------------------------------------
# Sets XMIN, YMIN, XMAX, YMAX variables from the region definition for REGION_TAG.
# If REGION_TAG is not recognized, prints an error and returns 1.
#
# Usage:
#   export REGION_TAG="XYZ"
#   source region_defns.sh
#   get_region_coordinates  # => sets XMIN, YMIN, XMAX, YMAX
# ------------------------------------------------------------------------------
function get_region_coordinates() {
    local coords="${REGION_COORDINATES[$REGION_TAG]}"
    if [ -z "$coords" ]; then
        echo "ERROR: Unknown REGION_TAG: $REGION_TAG" >&2
        return 1
    fi
    
    # Parse the coordinate quadruple from parentheses
    read XMIN YMIN XMAX YMAX <<< "${coords//[()]/}"

    # Export them for use by the caller
    export XMIN YMIN XMAX YMAX
}

export -f get_region_coordinates

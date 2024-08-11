
#==============================================================================
#  Date      Vers   Who  Description
# -----------------------------------------------------------------------------
# 10-Aug-24  1.0.0  DWW  Initial Creation
#==============================================================================
BC_EMU_API_VERSION=1.0.0
VALID_RTL_TYPE=8102024

# "pcireg" relies on this being set appropriately
pcireg_device=10ee:903f

    BASE_ADDR0=0x1000
    BASE_ADDR1=0x2000
REG_ETH_STATUS=0x3000
 
 REG_CLEAR_COUNTERS=$((0x00 * 4))
   REG_GOOD_PACKETS=$((0x10 * 4))
    REG_BAD_PACKETS=$((0x12 * 4))
REG_UNCLASS_PACKETS=$((0x14 * 4))  
         REG_RANGE0=$((0x20 * 4))
       REG_COUNTER0=$((0x30 * 4))


#==============================================================================
# This confirms that we have the correct RTL loaded into the FPGA
#==============================================================================
confirm_rtl()
{
    local REG_RTL_TYPE=20
    
    # Read the RTL_TYPE register
    local rtl_type=$(pcireg -dec $REG_RTL_TYPE)

    # If it's 0xFFFF_FFFF, we need to re-enumerate the PCI bus
    if [ $rtl_type -eq $((0xFFFFFFFF)) ]; then
        echo "Re-enumerating PCI bus..." 1>&2
        hot_reset 1>/dev/null 2>/dev/null
        rtl_type=$(pcireg -dec $REG_RTL_TYPE)        
    fi

    # echo a "1" for pass or a "0" for fail
    test $rtl_type -eq $VALID_RTL_TYPE && echo "1" || echo "0"
}
#==============================================================================


#==============================================================================
# Displays a 1 or 0 to indicate whether PCS alignment has been achieved
#==============================================================================
confirm_pcs_status()
{
    # Fetch the PCS-alignment status bits
    local status=$(pcireg -dec $REG_ETH_STATUS)

    # Display errors if it looks like the cables aren't connected
    test $((status & 1)) -eq 0 && echo "QSFP_0 isn't connected" 1>&2
    test $((status & 2)) -eq 0 && echo "QSFP_1 isn't connected" 1>&2

    # Display 1 or 0 to indicate both cables are plugged in (or not)
    test $status -eq 3 && echo "1" || echo "0"    
}
#==============================================================================


#==============================================================================
# $1 which range index, 0 thru 7
# $2 low value
# $3 high value (optional)
#==============================================================================
set_range()
{
    local index=$1
    local lo=$2
    local hi=$3

    # If there was no "hi" value given, hi is the same as low
    test -z $hi && hi=$lo


    # Ensure the caller gave us an index
    if [ "$index" == "" ]; then
        echo "Missing index on set_range()" 1>&2
        return
    fi

    # Ensure the index is in the correct range
    if [ $index -lt 0 ] || [ $index -gt 7 ]; then
        echo "Illegal index [$index] on set_range()" 1>&2
        return
    fi

    # Compute the offset of the relevant AXI register
    local offset=$((REG_RANGE0 + $index * 4))

    # hi/lo is stored in the upper/lower 16-bits of the register
    local value=$(( (hi << 16) | lo ))

    pcireg $((BASE_ADDR0 + offset)) $value
    pcireg $((BASE_ADDR1 + offset)) $value
}
#==============================================================================


#==============================================================================
# $1 which range index, 0 thru 7
#==============================================================================
get_range()
{
    local index=$1

    # Ensure the caller gave us an index
    if [ "$index" == "" ]; then
        echo "Missing index on set_range()" 1>&2
        return
    fi

    # Ensure the index is in the correct range
    if [ $index -lt 0 ] || [ $index -gt 7 ]; then
        echo "Illegal index [$index] on set_range()" 1>&2
        return
    fi

    # Compute the offset of the relevant AXI register
    local offset=$((REG_RANGE0 + $index * 4))

    # Display the value of the specified range register
    pcireg -dec $((BASE_ADDR0 + offset))
}
#==============================================================================



#==============================================================================
# $1 which channel, 0 or 1
# $2 which range index, 0 thru 7
#==============================================================================
range_packets()
{
    local channel=$1
    local   index=$2

    # Ensure we have a valid channel number
    if [ "$channel" != "0" ] && [ "$channel" != "1" ]; then
        echo "Illegal channel [$channel] on set_range()" 1>&2
        return
    fi

    # Ensure the caller gave us an index
    if [ "$index" == "" ]; then
        echo "Missing index on set_range()" 1>&2
        return
    fi

    # Ensure the index is in the correct range
    if [ $index -lt 0 ] || [ $index -gt 7 ]; then
        echo "Illegal index [$index] on set_range()" 1>&2
        return
    fi

    # Compute the offset of the relevant AXI register
    local offset=$((REG_COUNTER0 + $index * 8))

    # Display the value of the specified packet counter
    test $channel -eq 0 && pcireg -wide -dec $((BASE_ADDR0 + offset))
    test $channel -eq 1 && pcireg -wide -dec $((BASE_ADDR1 + offset))
}
#==============================================================================




#==============================================================================
# $1 which channel, 0 or 1
#==============================================================================
good_packets()
{
    local channel=$1

    # Ensure we have a valid channel number
    if [ "$channel" != "0" ] && [ "$channel" != "1" ]; then
        echo "Illegal channel [$channel] on good_packets()" 1>&2
        return
    fi

    # Compute the offset of the relevant AXI register
    local offset=$REG_GOOD_PACKETS

    # Display the value of the specified packet counter
    test $channel -eq 0 && pcireg -wide -dec $((BASE_ADDR0 + offset))
    test $channel -eq 1 && pcireg -wide -dec $((BASE_ADDR1 + offset))
}
#==============================================================================


#==============================================================================
# $1 which channel, 0 or 1
#==============================================================================
bad_packets()
{
    local channel=$1

    # Ensure we have a valid channel number
    if [ "$channel" != "0" ] && [ "$channel" != "1" ]; then
        echo "Illegal channel [$channel] on bad_packets()" 1>&2
        return
    fi

    # Compute the offset of the relevant AXI register
    local offset=$REG_BAD_PACKETS

    # Display the value of the specified packet counter
    test $channel -eq 0 && pcireg -wide -dec $((BASE_ADDR0 + offset))
    test $channel -eq 1 && pcireg -wide -dec $((BASE_ADDR1 + offset))
}
#==============================================================================


#==============================================================================
# $1 which channel, 0 or 1
#==============================================================================
unclass_packets()
{
    local channel=$1

    # Ensure we have a valid channel number
    if [ "$channel" != "0" ] && [ "$channel" != "1" ]; then
        echo "Illegal channel [$channel] on unclass_packets()" 1>&2
        return
    fi

    # Compute the offset of the relevant AXI register
    local offset=$REG_UNCLASS_PACKETS

    # Display the value of the specified packet counter
    test $channel -eq 0 && pcireg -wide -dec $((BASE_ADDR0 + offset))
    test $channel -eq 1 && pcireg -wide -dec $((BASE_ADDR1 + offset))
}
#==============================================================================



#==============================================================================
# Clears all packet counters
#==============================================================================
clear_counters()
{
    pcireg $((BASE_ADDR0 + REG_CLEAR_COUNTERS)) 1
    pcireg $((BASE_ADDR1 + REG_CLEAR_COUNTERS)) 1   
}
#==============================================================================



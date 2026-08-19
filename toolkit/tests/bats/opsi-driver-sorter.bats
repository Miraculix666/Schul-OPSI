#!/usr/bin/env bats

setup() {
    # Extract just the function we want to test to avoid running the whole script
    cat "$BATS_TEST_DIRNAME/../opsi-driver-sorter.sh" | awk '/^detect_device_category\(\) \{/{flag=1} flag; /^}/{if(flag){flag=0; exit}}' > "$BATS_TEST_DIRNAME/func_detect.sh"
    source "$BATS_TEST_DIRNAME/func_detect.sh"
}

teardown() {
    rm -f "$BATS_TEST_DIRNAME/func_detect.sh"
}

@test "detect_device_category - correctly identifies explicit device classes" {
    # Test network class (using lowercase "net")
    # Using printf instead of \n to avoid bash interpretation issues in string literals
    run detect_device_category "$(printf "Class=Net\nClassGUID={4d36e972-e325-11ce-bfc1-08002be10318}")"
    [ "$status" -eq 0 ]
    [ "$output" = "network" ]

    # Test display class
    run detect_device_category "Class = Display"
    [ "$status" -eq 0 ]
    [ "$output" = "display" ]

    # Test audio class
    run detect_device_category "class=\"media\""
    [ "$status" -eq 0 ]
    [ "$output" = "audio" ]
}

@test "detect_device_category - correctly identifies various explicit device classes" {
    run detect_device_category "Class=Bluetooth"
    [ "$output" = "bt" ]

    run detect_device_category "Class=USB"
    [ "$output" = "usb" ]

    run detect_device_category "Class=DiskDrive"
    [ "$output" = "storage" ]

    run detect_device_category "Class=Monitor"
    [ "$output" = "monitor" ]

    run detect_device_category "Class=Printer"
    [ "$output" = "printer" ]

    run detect_device_category "Class=Camera"
    [ "$output" = "camera" ]

    run detect_device_category "Class=Modem"
    [ "$output" = "modem" ]

    run detect_device_category "Class=Mouse"
    [ "$output" = "input" ]

    run detect_device_category "Class=Firmware"
    [ "$output" = "firmware" ]
}

@test "detect_device_category - falls back to guessing based on content" {
    # Test fallback to graphic
    run detect_device_category "$(printf "Class=Unknown\nDescription=Intel(R) HD Graphics")"
    [ "$status" -eq 0 ]
    [ "$output" = "graphic" ]

    # Test fallback to lan
    run detect_device_category "$(printf "Class=Other\nDescription=Ethernet Connection")"
    [ "$status" -eq 0 ]
    [ "$output" = "lan" ]

    # Test fallback to wlan (802.11 hits wlan rule if it doesn't contain 'network', so let's test just 'wireless')
    run detect_device_category "$(printf "Class=Other\nDescription=802.11 wireless adapter")"
    [ "$status" -eq 0 ]
    [ "$output" = "wlan" ]

    # Test fallback to raid
    run detect_device_category "$(printf "Class=Other\nDescription=SATA controller")"
    [ "$status" -eq 0 ]
    [ "$output" = "raid" ]

    # Test fallback to sensor
    run detect_device_category "$(printf "Class=Other\nDescription=Thermal controller")"
    [ "$status" -eq 0 ]
    [ "$output" = "sensor" ]

    # Test fallback to default system
    run detect_device_category "$(printf "Class=WeirdClass\nDescription=Some weird device")"
    [ "$status" -eq 0 ]
    [ "$output" = "system" ]
}

@test "detect_device_category - handles case-insensitivity" {
    run detect_device_category "CLASS=SYSTEM"
    [ "$status" -eq 0 ]
    [ "$output" = "system" ]
}

@test "detect_device_category - handles no class present" {
    run detect_device_category "$(printf "Description=Generic USB Hub\nDriverVer=12/12/2012")"
    [ "$status" -eq 0 ]
    [ "$output" = "system" ]
}

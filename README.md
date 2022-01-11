# Electron_MiSTer_tape
Electron Core with Tape support

This core has tape support by using the ADC input of the MiSTer. Note that the volume input needs to be exact, like with the original Electron.
The core implements the ADC by adding its input into the sys_top module and the Electron.sv. There also needs to be an inclusion of the tape module ltc2308.sv for this core to work

Changes are captured in screenshots in the changes folder

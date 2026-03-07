cd /tmp
swiftc ~/Downloads/MSIMuteLEDAgent_v4.2.0.swift \
    -o /tmp/MSIMuteLEDAgent_v420 \
    -framework Foundation \
    -framework CoreAudio \
    -framework IOKit \
    -framework CoreGraphics \
    -O

sudo cp /tmp/MSIMuteLEDAgent_v420 \
    "/Library/Application Support/MSIMuteLED/MSIMuteLEDAgent"

/Applications/MSIMuteLED.app/Contents/MacOS/MSIMuteLEDInstaller unregister
/Applications/MSIMuteLED.app/Contents/MacOS/MSIMuteLEDInstaller register

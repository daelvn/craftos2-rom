term.setGraphicsMode( true )
term.clear()
term.setGraphicsMode( false )
term.clear()
term.setCursorPos( 1, 1 )
for i = 0, 15 do term.setPaletteColor( 2^i, term.nativePaletteColor( 2^i ) ) end
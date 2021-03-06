
-- Setup process switching
local parentTerm = term.current()
local w,h = parentTerm.getSize()

local tProcesses = {}
local nCurrentProcess = nil
local nRunningProcess = nil
local bShowMenu = false
local bWindowsResized = false

local function selectProcess( n )
    if nCurrentProcess ~= n then
        if nCurrentProcess then
            local tOldProcess = tProcesses[ nCurrentProcess ]
            tOldProcess.window.setVisible( false )
        end
        nCurrentProcess = n
        if nCurrentProcess then
            local tNewProcess = tProcesses[ nCurrentProcess ]
            tNewProcess.window.setVisible( true )
            tNewProcess.bInteracted = true
        end
    end
end

local function setProcessTitle( n, sTitle )
    tProcesses[ n ].sTitle = sTitle
end

local function resumeProcess( nProcess, sEvent, ... )
    local tProcess = tProcesses[ nProcess ]
    local sFilter = tProcess.sFilter
    if sFilter == nil or sFilter == sEvent or sEvent == "terminate" then
        local nPreviousProcess = nRunningProcess
        nRunningProcess = nProcess
        term.redirect( tProcess.terminal )
        local ok, result = coroutine.resume( tProcess.co, sEvent, ... )
        tProcess.terminal = term.current()
        if ok then
            tProcess.sFilter = result
        else
            printError( result )
        end
        nRunningProcess = nPreviousProcess
    end
end

local function launchProcess( tProgramEnv, sProgramPath, ... )
    local tProgramArgs = table.pack( ... )
    local nProcess = #tProcesses + 1
    local tProcess = {}
    tProcess.sTitle = fs.getName( sProgramPath )
    if bShowMenu then
        tProcess.window = window.create( parentTerm, 1, 2, w, h-1, false )
    else
        tProcess.window = window.create( parentTerm, 1, 1, w, h, false )
    end
    tProcess.co = coroutine.create( function()
        os.run( tProgramEnv, sProgramPath, table.unpack( tProgramArgs, 1, tProgramArgs.n ) )
        if not tProcess.bInteracted then
            term.setCursorBlink( false )
            print( "Press any key to continue" )
            os.pullEvent( "char" )
        end
    end )
    tProcess.sFilter = nil
    tProcess.terminal = tProcess.window
    tProcess.bInteracted = false
    tProcesses[ nProcess ] = tProcess
    resumeProcess( nProcess )
    return nProcess
end

local function cullProcess( nProcess )
    local tProcess = tProcesses[ nProcess ]
    if coroutine.status( tProcess.co ) == "dead" then
        if nCurrentProcess == nProcess then
            if nProcess > 1 then
                selectProcess( nProcess - 1 )
            elseif #tProcesses > 1 then
                selectProcess( 1 )
            end
        end
        local e = #tProcesses
        for i = nProcess, e - 1 do tProcesses[i] = tProcesses[i+1] end
        tProcesses[e] = nil
        return true
    end
    return false
end

local function cullProcesses()
    local culled = false
    for n=#tProcesses,1,-1 do
        culled = culled or cullProcess( n )
    end
    return culled
end

-- Setup the main menu
local menuMainTextColor, menuMainBgColor, menuOtherTextColor, menuOtherBgColor
if parentTerm.isColor() then
    menuMainTextColor, menuMainBgColor = colors.yellow, colors.black
    menuOtherTextColor, menuOtherBgColor = colors.black, colors.gray
else
    menuMainTextColor, menuMainBgColor = colors.white, colors.black
    menuOtherTextColor, menuOtherBgColor = colors.black, colors.gray
end

local scrollPosition = 0
local menuLength = 0
local function redrawMenu()
    if bShowMenu then
        -- Draw menu
        parentTerm.setCursorPos( 1, 1 )
        parentTerm.setBackgroundColor( menuOtherBgColor )
        parentTerm.clearLine()
        local pos = -scrollPosition
        for n=1,#tProcesses do
            if n == nCurrentProcess then
                parentTerm.setTextColor( menuMainTextColor )
                parentTerm.setBackgroundColor( menuMainBgColor )
            else
                parentTerm.setTextColor( menuOtherTextColor )
                parentTerm.setBackgroundColor( menuOtherBgColor )
            end
            local line = " " .. tProcesses[n].sTitle .. " "
            if pos >= 0 then
                parentTerm.write( line )
            elseif pos + string.len( line ) >= 0 then
                parentTerm.write( string.sub( line, -pos ) )
            end
            pos = pos + string.len( line )
        end
        menuLength = pos + scrollPosition

        if menuLength > parentTerm.getSize() and scrollPosition + parentTerm.getSize() > menuLength then
            scrollPosition = menuLength - parentTerm.getSize()
            return redrawMenu()
        end

        -- Put the cursor back where it should be
        local tProcess = tProcesses[ nCurrentProcess ]
        if tProcess then
            tProcess.window.restoreCursor()
        end
    end
end

local function resizeWindows()
    local windowY, windowHeight
    if bShowMenu then
        windowY = 2
        windowHeight = h-1
    else
        windowY = 1
        windowHeight = h
    end
    for n=1,#tProcesses do
        local tProcess = tProcesses[n]
        local window = tProcess.window
        local x,y = tProcess.window.getCursorPos()
        if y > windowHeight then
            tProcess.window.scroll( y - windowHeight )
            tProcess.window.setCursorPos( x, windowHeight )
        end
        tProcess.window.reposition( 1, windowY, w, windowHeight )
    end
    bWindowsResized = true
end

local function setMenuVisible( bVis )
    if bShowMenu ~= bVis then
        bShowMenu = bVis
        resizeWindows()
        redrawMenu()
    end
end

local multishell = {}

function multishell.getFocus()
    return nCurrentProcess
end

function multishell.setFocus( n )
    if type( n ) ~= "number" then
        error( "bad argument #1 (expected number, got " .. type( n ) .. ")", 2 )
    end
    if n >= 1 and n <= #tProcesses then
        selectProcess( n )
        redrawMenu()
        return true
    end
    return false
end

function multishell.getTitle( n )
    if type( n ) ~= "number" then
        error( "bad argument #1 (expected number, got " .. type( n ) .. ")", 2 )
    end
    if n >= 1 and n <= #tProcesses then
        return tProcesses[n].sTitle
    end
    return nil
end

function multishell.setTitle( n, sTitle )
    if type( n ) ~= "number" then
        error( "bad argument #1 (expected number, got " .. type( n ) .. ")", 2 )
    end
    if type( sTitle ) ~= "string" then
        error( "bad argument #2 (expected string, got " .. type( sTitle ) .. ")", 2 )
    end
    if n >= 1 and n <= #tProcesses then
        setProcessTitle( n, sTitle )
        redrawMenu()
    end
end

function multishell.getCurrent()
    return nRunningProcess
end

function multishell.launch( tProgramEnv, sProgramPath, ... )
    if type( tProgramEnv ) ~= "table" then
        error( "bad argument #1 (expected table, got " .. type( tProgramEnv ) .. ")", 2 )
    end
    if type( sProgramPath ) ~= "string" then
        error( "bad argument #2 (expected string, got " .. type( sProgramPath ) .. ")", 2 )
    end
    local previousTerm = term.current()
    setMenuVisible( (#tProcesses + 1) >= 2 )
    local nResult = launchProcess( tProgramEnv, sProgramPath, ... )
    redrawMenu()
    term.redirect( previousTerm )
    return nResult
end

function multishell.getCount()
    return #tProcesses
end

-- Begin
parentTerm.clear()
setMenuVisible( false )
selectProcess( launchProcess( {
    ["shell"] = shell,
    ["multishell"] = multishell,
}, "/rom/programs/shell.lua", ... ) )
redrawMenu()

local ctrlHeld = false

-- Run processes
while #tProcesses > 0 do
    -- Get the event
    local tEventData = table.pack( os.pullEventRaw() )
    local sEvent = tEventData[1]
    if sEvent == "term_resize" then
        -- Resize event
        w,h = parentTerm.getSize()
        resizeWindows()
        redrawMenu()

    elseif sEvent == "char" or sEvent == "key" or sEvent == "key_up" or sEvent == "paste" or sEvent == "terminate" then
        -- Keyboard event
        if sEvent == "key" and (tEventData[2] == keys.leftCtrl or tEventData[2] == keys.rightCtrl) then
            ctrlHeld = true
        elseif sEvent == "key_up" and (tEventData[2] == keys.leftCtrl or tEventData[2] == keys.rightCtrl) then
            ctrlHeld = false
        end
        if sEvent == "key" and ctrlHeld and #tProcesses > 1 and tEventData[2] == keys.left then
            selectProcess( nCurrentProcess - 1 < 1 and #tProcesses or nCurrentProcess - 1 )
            redrawMenu()
        elseif sEvent == "key" and ctrlHeld and #tProcesses > 1 and tEventData[2] == keys.right then
            selectProcess( nCurrentProcess + 1 > #tProcesses and 1 or nCurrentProcess + 1 )
            redrawMenu()
        else
            -- Passthrough to current process
            resumeProcess( nCurrentProcess, table.unpack( tEventData, 1, tEventData.n ) )
        end
        if cullProcess( nCurrentProcess ) then
            setMenuVisible( #tProcesses >= 2 )
            redrawMenu()
        end

    elseif sEvent == "mouse_click" then
        -- Click event
        local button, x, y = tEventData[2], tEventData[3], tEventData[4]
        if bShowMenu and y == 1 then
            -- Switch process
            local tabStart = 1
            x = x + scrollPosition
            for n=1,#tProcesses do
                local tabEnd = tabStart + string.len( tProcesses[n].sTitle ) + 1
                if x >= tabStart and x <= tabEnd then
                    selectProcess( n )
                    redrawMenu()
                    break
                end
                tabStart = tabEnd + 1
            end
        else
            -- Passthrough to current process
            resumeProcess( nCurrentProcess, sEvent, button, x, (bShowMenu and y-1) or y )
            if cullProcess( nCurrentProcess ) then
                setMenuVisible( #tProcesses >= 2 )
                redrawMenu()
            end
        end

    elseif sEvent == "mouse_scroll" then
        -- Mouse scroll event
        local p1, x, y = tEventData[2], tEventData[3], tEventData[4]
        if not (bShowMenu and y == 1) then
            -- Passthrough to current process
            resumeProcess( nCurrentProcess, sEvent, p1, x, (bShowMenu and y-1) or y )
            if cullProcess( nCurrentProcess ) then
                setMenuVisible( #tProcesses >= 2 )
                redrawMenu()
            end
        else
            -- Scroll menu
            if menuLength > parentTerm.getSize() and ((p1 > 0 and scrollPosition + parentTerm.getSize() <= menuLength) or (p1 < 0 and scrollPosition > 0)) then
                scrollPosition = scrollPosition + p1
                redrawMenu()
            end
        end
    
    elseif sEvent == "mouse_drag" or sEvent == "mouse_up" then
        -- Other mouse event
        local p1, x, y = tEventData[2], tEventData[3], tEventData[4]
        if not (bShowMenu and y == 1) then
            -- Passthrough to current process
            resumeProcess( nCurrentProcess, sEvent, p1, x, (bShowMenu and y-1) or y )
            if cullProcess( nCurrentProcess ) then
                setMenuVisible( #tProcesses >= 2 )
                redrawMenu()
            end
        end

    else
        -- Other event
        -- Passthrough to all processes
        local nLimit = #tProcesses -- Storing this ensures any new things spawned don't get the event
        for n=1,nLimit do
            resumeProcess( n, table.unpack( tEventData, 1, tEventData.n ) )
        end
        if cullProcesses() then
            setMenuVisible( #tProcesses >= 2 )
            redrawMenu()
        end
    end

    if bWindowsResized then
        -- Pass term_resize to all processes
        local nLimit = #tProcesses -- Storing this ensures any new things spawned don't get the event
        for n=1,nLimit do
            resumeProcess( n, "term_resize" )
        end
        bWindowsResized = false
        if cullProcesses() then
            setMenuVisible( #tProcesses >= 2 )
            redrawMenu()
        end
    end
end

-- Shutdown
term.redirect( parentTerm )

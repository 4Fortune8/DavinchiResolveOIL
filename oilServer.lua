local socket = require("ljsocket")
local json = require("dkjson")
local ffi = require("ffi")

local os_name = ffi.os

print("Operating System: " .. os_name)


local command_close

if os_name == "Windows" then
    -- Define the necessary Windows API functions using FFI
    -- Note: Sleep and ShellExecuteA are used to prevent terminal from opening (replaces os.execute)
    ffi.cdef [[
        typedef wchar_t WCHAR;

        int MultiByteToWideChar(
            unsigned int CodePage,
            unsigned long dwFlags,
            const char* lpMultiByteStr,
            int cbMultiByte,
            WCHAR* lpWideCharStr,
            int cchWideChar);

        void* _wfopen(const WCHAR* filename, const WCHAR* mode);
        size_t fread(void* buffer, size_t size, size_t count, void* stream);
        int fclose(void* stream);
        void Sleep(unsigned int ms);
        int ShellExecuteA(void* hwnd, const char* lpOperation, const char* lpFile, const char* lpParameters, const char* lpDirectory, int nShowCmd);
    ]]

elseif os_name == "OSX" then
    -- Use the C system function to execute shell commands on macOS
    ffi.cdef [[ int system(const char *command); ]]

   
else
    print("Unsupported OS")
    return
end


fusion = resolve:Fusion()
project = resolve:GetProjectManager():GetCurrentProject()
mediaPool = project:GetMediaPool()
rootFolder = mediaPool:GetRootFolder()
currentProject = project:GetName()



function sanitize_filename(filename)
    return filename:gsub("[^%w%-_%. ]", "_")
end

function download_file(url, getfilepath)
    local sanitized_url = sanitize_filename(url)
    print('curl  --create-dirs -O --output-dir "' .. getfilepath .. '" "' .. url .. '"')
    os.execute('curl  --create-dirs -O --output-dir "' .. getfilepath .. '" "' .. url .. '"')
end


function receive_text(data)
    local text = data.releventString or ""
    
    local response = {
        url = text,
        message = "url received successfully"
    }
    print(response)
    return response
end

-- Server
local port = 55500

-- Set up server socket configuration
local info = socket.find_first_address("*", port)
local server = assert(socket.create(info.family, info.socket_type, info.protocol))
print("AutoSubs server is listening on port: ", port)

-- Set socket options
server:set_blocking(false)
assert(server:set_option("nodelay", true, "tcp"))
assert(server:set_option("reuseaddr", true))

-- Bind and listen
assert(server:bind(info))
assert(server:listen())

function CreateResponse(body)
    local header = "HTTP/1.1 200 OK\r\n" ..
                   "Server: ljsocket/0.1\r\n" ..
                   "Content-Type: application/json\r\n" ..
                   "Content-Length: " .. #body .. "\r\n" ..
                   "Connection: close\r\n" ..
                   "Access-Control-Allow-Origin: *\r\n" ..  -- Add CORS header
                   "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" ..  -- Add allowed methods
                   "Access-Control-Allow-Headers: Content-Type\r\n" ..  -- Add allowed headers
                   "\r\n"

    local response = header .. body
    return response
end

function AddMediaToBin(data, filePath,boolCurl)
    print("Adding media to bin")
    local mediaStorage = resolve:GetMediaStorage()
    local files = mediaStorage:GetFileList(filePath)
    local newFiles = {}
    local success, err = pcall(function()
        for _, record in ipairs(files) do
            newFiles[record] = true
        end
    end)
    if not success then
        print("Error while processing files:", err)
    end
    download_file(data, filePath)
    
        local mediaStorage = resolve:GetMediaStorage()
    local files = mediaStorage:GetFileList(filePath)
      -- Step 2: Compare new records against the old records set
    for _, newRecord in ipairs(files) do
        -- Step 3: If the record doesn't exist in oldSet, it's new and we should do something
        if not newFiles[newRecord] then
            -- Perform your operation here
            -- For example, print a message or call a function:
                mediaStorage:AddItemListToMediaPool(newRecord)
            print("New record found:", newRecord)
        end
    end
end


function refreshProject()
    print("starting Refresh")
    fusion = resolve:Fusion()
    project = resolve:GetProjectManager():GetCurrentProject()
    print(project)
    print(fusion)
    mediaPool = project:GetMediaPool()
    rootFolder = mediaPool:GetRootFolder()
    currentProject = project:GetName()
end


local oldfilePath = ''
function startCooking()
    local refresh = true   

    print("[AutoSubs Server] Cooked With OIL")                        
    local mountedVolumeList = resolve:GetMediaStorage():GetMountedVolumes()
    local rootFolder = mountedVolumeList[1]
    print("rootFolder: ", rootFolder)
    local currentProject = project:GetName()
    print("currentProject: ", currentProject)
    local filePath = rootFolder .. '/' .. currentProject
    print("Mounted Volume List: ", filePath)
    if (oldfilePath ~= filePath) then
        print('mkdir "' .. filePath .. '"')
        os.execute('mkdir "' .. filePath .. '"')
        oldfilePath = filePath
        

    end
    return filePath
    
end

function sleep(n)
    if os_name == "Windows" then
        -- Windows
        ffi.C.Sleep(n * 1000)
    else
        -- Unix-based (Linux, macOS)
        os.execute("sleep " .. tonumber(n))
    end
end


local quitServer = false
while not quitServer do
	

    -- Check if DaVinci Resolve is still running
    if not resolve then
        print("DaVinci Resolve is not running. Shutting down server...")
        quitServer = true
        client:close()
        break
    end
    -- Server loop to handle client connections
    local client, err = server:accept()
    if client then
        local peername, peer_err = client:get_peer_name()
        if peername then
            assert(client:set_blocking(false))
            -- Try to receive data (example HTTP request)
            local str, err = client:receive()
            if not project:GetName() then 
                refreshProject()
                sleep(200)
            end

            if str then
                print("Received request:", str)
                -- Split the request by the double newline
                local header_body_separator = "\r\n\r\n"
                local _, _, content = string.find(str, header_body_separator .. "(.*)")
                print("Received request:", content)

                -- Parse the JSON content
                local data, pos, err = json.decode(content, 1, nil)
                local body = ""
                print("Data:", data)
                local success, err = pcall(function()
                    if data == nil then
                        body = json.encode({
                            message = "Invalid JSON data"
                        })
                        print("Invalid JSON data")
                    elseif data.func == "save_image" then -- this is h                                  
                        local filePath = startCooking()
                        print("Mounted Volume List: ", filePath)
                        AddMediaToBin(data.releventString,filePath)
                        print(project)
print(fusion)
                        body = json.encode({
                            message = "Job completed"
                        })

                        elseif data.func == "save_alternative" then -- this is h
                        local filePath = startCooking()
                        AddMediaToBin(data.releventString,filePath)
                        body = json.encode({
                            message = "Job completed"
                        })

                        
                    elseif data.func == "Exit" then
                        print("Exiting server")
                        quitServer = true
                        body = json.encode({
                            message = "Job completed"
                        })
                    else
                        print("Invalid function name")
                    end
                end)

                if not success then
                    body = json.encode({
                        message = "Job failed with error: " .. err
                    })
                    print("Error:", err)
                end
                print("Response:", body)
                -- Send HTTP response content
                local response = CreateResponse(body)
                assert(client:send(response))
                -- Close connection
                client:close()
                
            elseif err == "closed" then
                client:close()
            elseif err ~= "timeout" then
                error(err)
            end
        end
    elseif err ~= "timeout" then
        error(err)
    end

    sleep(1)  -- Replace sleep with ffi.C.Sleep (100 ms)

end

print("Shutting down AutoSubs server...")
itm.Message.Text = "Shutting down..."
server:close()
win:Hide()
print("Server shut down.")

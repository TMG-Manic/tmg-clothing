local TMGCore = exports['tmg-core']:GetCoreObject()


RegisterServerEvent("tmg-clothing:saveSkin", function(model, skin)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not model or not skin then return end

    local citizenid = Player.PlayerData.citizenid

    local skinData = {
        citizenid = citizenid,
        model = model,
        skin = skin,
        active = 1
    }

    local success = exports['tmgnosql']:UpdateOne('playerskins', 
        { ["citizenid"] = citizenid }, 
        { ["$set"] = skinData }, 
        { ["upsert"] = true }
    )

    if success then
        print(string.format("^5[TMG]^7 Mainframe: Skin matrix anchored for Citizen %s", citizenid))
    else
        print(string.format("^1[TMG]^7 Mainframe Error: Failed to anchor skin for %s", citizenid))
    end
end)

RegisterServerEvent("tmg-clothes:loadPlayerSkin", function()
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    
    if not Player then return end

    local result = exports['tmgnosql']:FetchOne('playerskins', { 
        ["citizenid"] = Player.PlayerData.citizenid, 
        ["active"] = 1 
    })
    
    if result then
        TriggerClientEvent("tmg-clothes:loadSkin", src, false, result.model, result.skin)
        print(string.format("^5[TMG]^7 Mainframe: Identity matrix streamed for %s", Player.PlayerData.citizenid))
    else
        TriggerClientEvent("tmg-clothes:loadSkin", src, true)
        print(string.format("^5[TMG]^7 Mainframe: No skin matrix found for %s. Initializing generator.", Player.PlayerData.citizenid))
    end
end)

-- [[ TMG MAINFRAME: OUTFIT MANAGEMENT ]]

RegisterServerEvent("tmg-clothes:saveOutfit", function(outfitName, model, skinData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    
    if not Player or not model or not skinData then return end

    local outfitId = string.format("outfit-%d-%d", math.random(1, 10), math.random(1111, 9999))
    
    local data = {
        citizenid = Player.PlayerData.citizenid,
        outfitname = outfitName,
        model = model,
        skin = skinData, 
        outfitId = outfitId
    }

    local insertSuccess = exports['tmgnosql']:UpdateMany('player_outfits', data)
    
    if insertSuccess then
        local result = exports['tmgnosql']:Fetch('player_outfits', { 
            ["citizenid"] = Player.PlayerData.citizenid 
        })
        
        local reloadData = (result and #result > 0) and result or nil
        TriggerClientEvent('tmg-clothing:client:reloadOutfits', src, reloadData)
        
        print(string.format("^5[TMG]^7 Mainframe: New outfit '%s' anchored for %s", outfitName, Player.PlayerData.citizenid))
    else
        print(string.format("^1[TMG]^7 Mainframe Error: Failed to save outfit '%s'", outfitName))
    end
end)

RegisterServerEvent("tmg-clothing:server:removeOutfit", function(outfitName, outfitId)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    local deleteSuccess = exports['tmgnosql']:DeleteOne('player_outfits', { 
        ["citizenid"] = citizenid, 
        ["outfitId"] = outfitId 
    })

    if deleteSuccess then
        local result = exports['tmgnosql']:Fetch('player_outfits', { 
            ["citizenid"] = citizenid 
        })
        
        local reloadData = (result and #result > 0) and result or nil
        TriggerClientEvent('tmg-clothing:client:reloadOutfits', src, reloadData)
        
        print(string.format("^5[TMG]^7 Mainframe: Outfit matrix '%s' purged for %s", outfitId, citizenid))
    else
        print(string.format("^1[TMG]^7 Mainframe Error: Failed to purge outfit %s", outfitId))
    end
end)

-- [[ TMG MAINFRAME: DATA CALLBACKS ]]

TMGCore.Functions.CreateCallback('tmg-clothing:server:getOutfits', function(source, cb)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    
    if not Player then return cb({}) end

    local result = exports['tmgnosql']:Fetch('player_outfits', { 
        ["citizenid"] = Player.PlayerData.citizenid 
    })
    
    cb(result or {})

    print(string.format("^5[TMG]^7 Mainframe: Wardrobe manifest streamed for %s", Player.PlayerData.citizenid))
end)
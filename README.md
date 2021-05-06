# Sandbox
Sandbox is Custom dynamic game type controller for SAPP, instead of using the builtin "events"
system from SAPP, Sandbox provides different actions and precreated events ready to be used on
specific gametypes files per map as simple YAML file:
```yml
name: Assasin
description: Get camo with every kill!
version: 1
baseGameType: slayer
events:
  OnPlayerSpawn:
    general:
      actions:
        - name: eraseWeapons
        - name: addPlayerWeapon
          params:
            weapon: "[shm]\\halo_4\\weapons\\sniper rifle\\sniper rifle"
  OnPlayerKill:
    general:
      actions:
        - name: setPlayerCamo
```

## Per Map Gametypes Structure
Sandbox provides a way to deal with the organization of different map files and tons of other
gametypes that are designed for specific maps:
```
gametypes/
    forge_island/
        - assasin.yml
    bloodgulch/
        - fatrat.yml
    bigass/
        - zombies.yml
``` 

## Why should I use it?
In contrast with the events system every gametype executed here is dynamic and can be replaced at any time on the game, you can load any other gametype dynamically if needed by just using this 
command:
```
lg assasin
```

# Contribute to Sandbox
All the sandbox project is on the works and every help is welcome! Do not forget to join us on the [Shadowmods Discord Server](https://discord.shadowmods.net) if you want to discuss and talk about this or other projects for Halo Custom Edition.

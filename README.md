# armatactics-linux-fix

Makes the native **Linux** version of **Arma Tactics** (Steam, App ID 224860) start again.

The script patches a few bytes in two game files. It does not download or ship any game files, and it only changes files whose SHA-256 matches the known Steam build.

## Symptoms

| What you see | Cause | Fix |
|---|---|---|
| The game quits a second or two after launch, with no window or only a brief flash. `~/.config/unity3d/Player.log` contains `Player is already running`. | Unity's single-instance check gives a false positive (see below). | `ArmaTactics.x86`, 3 bytes |
| The game opens, then a red **ERROR** message appears and the only option is to quit. | The game's settings file in Steam Cloud (`registry`) is empty (0 bytes). | `Assembly-CSharp.dll`, 49 bytes |

## Usage

1. Close the game.
2. Download and run the script:

   ```bash
   curl -LO https://raw.githubusercontent.com/marciocr/armatactics-linux-fix/main/armatactics-linux-fix.sh
   chmod +x armatactics-linux-fix.sh
   ./armatactics-linux-fix.sh
   ```

3. Start the game from Steam as usual.

The script finds the game in any Steam library folder, including Flatpak Steam. If it doesn't find yours, pass the game folder as an argument:

```bash
./armatactics-linux-fix.sh "/path/to/SteamLibrary/steamapps/common/ArmaTactics"
```

You can run the script more than once. Files that are already patched are left alone.

Requirements: `bash`, `sha256sum`, `dd`, and the other coreutils every Linux distribution ships.

### Undo

Run **Verify integrity of game files** in Steam (game Properties → Installed Files), or reinstall the game. A game update also restores the original files; just run the script again afterwards.

## Technical details

### 1. "Player is already running" (`ArmaTactics.x86`)

The game is built with Unity 5.3.6. On Linux, the Unity player prevents a second instance by scanning `/proc/[0-9]*/cmdline`, running `realpath()` on each process's `argv[0]`, and comparing the result with its own executable.

Current Steam clients start some `steamwebhelper` processes with `argv[0]` set to `/proc/self/exe`. When the *game* resolves that path, `/proc/self` is the game's own process, so it resolves to `ArmaTactics.x86`. The game concludes that it is already running and exits. This happens every time Steam is running, which is always the case when you launch through Steam.

The patch makes that check function return 0 ("no other instance"):

```
file offset 0xa8c6c0:  55 b9 00  ->  31 c0 c3   (xor eax, eax ; ret)
```

### 2. Red ERROR on start (`Assembly-CSharp.dll`)

At startup, the game downloads its settings file, `registry`, from Steam Cloud. In `CGameServicesSteam.StartDownload`:

- If the file **does not exist**, the game reports `NOT_FOUND`, creates default settings and continues.
- If the file **exists but is 0 bytes long**, the game reports `READY` with empty contents. `Registry.LoadingCoroutine` then shows `ERROR (ERR_REGISTRY_EMPTY)` and loads the abort scene.

A 0-byte `registry` entry can be left behind in Steam Cloud, and then the game cannot start until something writes a valid file. That is why the known Windows workaround ("run the demo first") helps.

The patch makes `StartDownload` treat a 0-byte cloud file the same as a missing one:

```csharp
if (SteamRemoteStorage.FileExists(name) && SteamRemoteStorage.GetFileSize(name) != 0)
    { /* read file -> READY */ }
else
    { /* NOT_FOUND -> game creates defaults */ }
```

It is an in-place IL edit of the method body at file offset `0x8aff6`, 49 bytes long. The method's two long branches become short branches, which frees room for the extra `fileSize == 0` check, so the method size and all other offsets stay the same. Once the game has started, it saves a valid `registry` to Steam Cloud again.

### Supported files

| File | Original SHA-256 | Patched SHA-256 |
|---|---|---|
| `ArmaTactics.x86` | `b363ae47469fbb359de4da43f8cb45a4e58e46935ba25070b66a63d6ac125a81` | `a2fc24be19e1365671129cc670f6756ae411fe927d640d7bed4afa994149e34c` |
| `ArmaTactics_Data/Managed/Assembly-CSharp.dll` | `f8c468ce71b76df84f70354d08a59b4019c617226395fad3e36a655eea857dd8` | `56ae673b314ba942ca8bec054641cd7467a132742670fc1dfe01b3e6b5d7b10c` |

If your files have a different hash, the script stops and changes nothing. Please open an issue and include the hash it printed.

## Disclaimer

This is an unofficial community fix, not affiliated with or endorsed by Bohemia Interactive or Valve. Arma Tactics is a trademark of Bohemia Interactive. You use the script at your own risk.

## License

[MIT](LICENSE)

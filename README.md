# ftmo-1step-ea

MetaTrader 5 Expert Advisor for an FTMO 1-Step challenge.

> Status: project scaffold only. Strategy spec pending; no strategy code yet.

## Environment

| Item | Path |
|---|---|
| MetaEditor | `D:\Program Files (x86)\New folder\MetaEditor64.exe` |
| MT5 data folder | `C:\Users\visio\AppData\Roaming\MetaQuotes\Terminal\FD4EE2C8A393414AD14B68905678707F` |

## Building

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compile.ps1 path\to\EA.mq5
```

The script runs MetaEditor headless, prints errors/warnings, and exits `0` only when
the log reports `0 errors` (MetaEditor's own exit code is not reliable).
Standard library includes (e.g. `<Trade\Trade.mqh>`) resolve from the data folder's `MQL5\Include`.

Source files should be saved as UTF-8 so git can diff them (MetaEditor may default to UTF-16).

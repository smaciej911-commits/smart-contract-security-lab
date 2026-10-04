# 03 — Parity multisig: zamrożenie współdzielonej biblioteki

## Historical Exploit Reproduction

```yaml
Chain: Ethereum mainnet
Block: 4501735 (stan przed incydentem; fork testowy)
Vulnerable library: 0x863DF6BFa4469f3ead0bE8F9F2AAE51c91A907b4
Incident date: 2017-11-06
Impact: 513,774.16 ETH w 587 portfelach stało się niedostępne
Attack transactions:
  initialize: 0x05f71e1b2cb4f03e547739db15d080fd30c989eda04d37ce6264c5686e0722c9
  selfdestruct: 0x47f7cff7a5e671884629c93b368cb18f58a993f4b19c2a53a8662e3f1482f690
```

## 1. Stan protokołu przed incydentem

Portfele multisig były cienkimi kontraktami, które delegowały logikę do jednej współdzielonej biblioteki. Sama biblioteka pozostawała niezainicjalizowana we własnym storage.

Test wybiera fork z bloku `4,501,735`, z archiwalnego źródła Ethereum. W tym stanie kod biblioteki jest obecny, a testowy kontrakt nie jest jej właścicielem. Konfiguracja Foundry przypina EVM do reguł Paris, sprzed zmiany semantyki `SELFDESTRUCT` w Cancun.

## 2. Podatność

Publiczne `initWallet` sprawdzało tylko, czy liczba właścicieli wynosi zero. Warunek był prawdziwy w storage samej biblioteki. Dowolny caller mógł więc zainicjalizować bibliotekę bezpośrednio i ustawić próg wymaganych potwierdzeń na zero.

## 3. Anatomia transakcji atakującego

1. `initWallet([caller], 0, 0)` ustawiło wywołującego jako właściciela biblioteki.
2. `kill(caller)` przeszło przy progu zero i uruchomiło `selfdestruct` biblioteki.
3. Każdy portfel zależny od jej kodu stracił możliwość wykonania logiki biblioteki. Środki zostały zablokowane, a nie wypłacone przez atakującego.

Test odtwarza oba wywołania bezpośrednio na historycznym adresie w lokalnym fork EVM, używając adresu atakującego jako nadawcy. Nie wysyła transakcji do publicznej sieci.

## 4. Root cause

- współdzielona biblioteka miała publiczny initializer i nie zablokowała własnego storage przy wdrożeniu;
- biblioteka zachowała funkcję `kill`, której nie potrzebowała jako wspólny komponent logiki;
- wszystkie portfele polegały na kodzie pod jednym adresem, więc usunięcie tego kodu uszkodziło wiele niezależnych portfeli.

## 5. Odtworzenie Foundry

Test forkowy leży poza domyślnym lokalnym suite. Wymaga archiwalnego RPC. Profil `historical` wybiera katalog `fork-test/`; w PowerShell ustaw zmienne przed poleceniem:

```powershell
$env:MAINNET_RPC_URL = "https://your-archive-rpc"
$env:FOUNDRY_PROFILE = "historical"
forge test --match-test testExploit_ReproduceParityLibraryFreezeOnHistoricalFork -vvvv
```

Test przypina fork do bloku `4,501,735`, potwierdza stan początkowy, następnie odtwarza `initWallet` i `kill` z adresem historycznego atakującego jako nadawcą. Asercje potwierdzają, że biblioteka akceptuje initializer i że późniejsze `kill` wraca bez revertu. Usunięcie kodu przez `selfdestruct` następuje na granicy transakcji; nie należy wnioskować o tym efekcie z odczytu kodu w środku tego samego testu. Całość działa na lokalnym forku; test nie broadcastuje transakcji.

## 6. Poprawka

Model `FixedProtocol.sol` blokuje storage współdzielonej implementacji w konstruktorze i pomija `kill`. Proxy korzystające z `delegatecall` zachowują własne storage, więc initializer może działać jednorazowo w kontekście konkretnego portfela.

To demonstracja poprawki, nie zamiennik wdrażalnego patcha dla historycznej biblioteki. W proxy systemie rzeczywistym każda zmiana musi zachować układ storage; starsze, już wdrożone portfele nie są naprawiane przez samą nową implementację.

## 7. Invariant i test regresyjny

Współdzielona implementacja po wdrożeniu pozostaje zainicjalizowana, nie uzyskuje właściciela przez bezpośredni initializer i nie udostępnia funkcji `kill`. Lokalny test sprawdza revert przy inicjalizacji i brak selektora `kill(address)`. Test invariantów fuzzuje próby ponownej inicjalizacji i wywołania usuniętej funkcji. Osobny workflow `Historical fork reproduction` można uruchomić ręcznie; używa sekretu `MAINNET_ARCHIVE_RPC_URL`.

```sh
forge test --match-path 'test/03-parity-library-freeze/Exploit.t.sol' --match-test testPatch -vvvv
forge test --match-path 'test/03-parity-library-freeze/Invariant.t.sol' -vvvv
```

## Źródła incydentu

- [Parity Technologies: postmortem](https://medium.com/paritytech/a-postmortem-on-the-parity-multi-sig-library-self-destruct-63daca3a4cf7)
- [Transakcja `initWallet`](https://etherscan.io/tx/0x05f71e1b2cb4f03e547739db15d080fd30c989eda04d37ce6264c5686e0722c9)
- [Transakcja `kill`](https://etherscan.io/tx/0x47f7cff7a5e671884629c93b368cb18f58a993f4b19c2a53a8662e3f1482f690)

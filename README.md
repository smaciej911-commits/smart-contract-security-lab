# Smart Contract Security & Invariant Testing Lab

Trzy małe, kompletne laboratoria pokazują podatność, jej wpływ, poprawkę i test zapobiegający regresji. Każdy przypadek ma model kontraktu, reprodukcję ataku, test poprawki oraz property-based invariant testing.

Repozytorium jest udostępnione na licencji MIT (zob. [LICENSE](LICENSE)). Kontrakty są edukacyjnymi modelami, nie kodem produkcyjnym ani audytowanymi implementacjami.

```text
src/
├── 01-oracle-manipulation/   # modele podatne i poprawione
├── 02-share-price-inflation/
└── 03-parity-library-freeze/
test/
├── 01-oracle-manipulation/   # reprodukcja, regresja i invarianty
├── 02-share-price-inflation/
└── 03-parity-library-freeze/
fork-test/
└── 03-parity-library-freeze/   # historyczny fork Ethereum, blok 4,501,735
```

Każdy przypadek ma modele `VulnerableProtocol.sol` i `FixedProtocol.sol` w `src/<case>/`, a `Exploit.t.sol`, `Invariant.t.sol` i `README.md` w `test/<case>/`. Kontrakty są małymi modelami edukacyjnymi, a nie gotowymi do wdrożenia protokołami.

## Wymagania

- Foundry (`forge`)
- Solidity 0.8.24; Foundry wybiera kompilator na podstawie `foundry.toml`
- Archiwalny endpoint Ethereum tylko dla historycznego testu Parity

Repozytorium nie wymaga `forge-std`, OpenZeppelin ani zewnętrznych bibliotek Solidity. Tokeny testowe mają publiczne `mint` i nie są przeznaczone do wdrożenia.

## Lokalne sprawdzenie i demonstracja

Z katalogu głównego:

```sh
forge fmt --check
forge build --sizes
forge test -vvv
```

Jedno polecenie `forge test -vvv` uruchamia dwa samodzielne exploity, testy poprawek, test poprawki Parity oraz handlery invariantów. Pełne ślady wszystkich testów pokaże `-vvvv`.

Pojedyncze reprodukcje z pełnym śladem:

```sh
forge test --match-path 'test/01-oracle-manipulation/Exploit.t.sol' --match-test testExploit -vvvv
forge test --match-path 'test/02-share-price-inflation/Exploit.t.sol' --match-test testExploit -vvvv
```

## Historyczny fork Parity

Test forkowy jest oddzielony profilem Foundry `historical`. Używa lokalnego forka przypiętego do bloku `4,501,735`; nie wysyła transakcji do sieci i nie wymaga klucza prywatnego. Potrzebny jest endpoint archiwalny, który udostępnia stan z tego bloku.

PowerShell:

```powershell
$env:MAINNET_RPC_URL = "https://your-archive-rpc"
$env:FOUNDRY_PROFILE = "historical"
forge test --match-test testExploit_ReproduceParityLibraryFreezeOnHistoricalFork -vvvv
```

Bash:

```sh
MAINNET_RPC_URL="https://your-archive-rpc" FOUNDRY_PROFILE=historical forge test --match-test testExploit_ReproduceParityLibraryFreezeOnHistoricalFork -vvvv
```

Workflow `Historical fork reproduction` można uruchomić ręcznie po ustawieniu sekretu GitHub `MAINNET_ARCHIVE_RPC_URL`. Zwykłe CI nie potrzebuje RPC.

## Zakres przypadków

| Przypadek | Co się psuje | Poprawka i regression check |
| --- | --- | --- |
| Oracle manipulation | Pożyczka używa chwilowej ceny spot z manipulowalnego poola | Niezależny feed, zakres konfiguracji LTV i blokada reentrancy; regresje sprawdzają atak, błędny LTV i callback przy spłacie |
| Share-price inflation | Bezpośrednia donacja zmienia cenę udziału i może wyzerować udziały ofiary po zaokrągleniu w dół | Wirtualne aktywa i udziały z blokadą reentrancy; regresja powtarza sekwencję pierwszego deponenta |
| Parity library freeze | Niezainicjalizowana współdzielona biblioteka pozwala na `initWallet` i `kill` | Model poprawki blokuje storage implementacji, usuwa `kill`; historyczny fork odtwarza sekwencję incydentu |

## Invariant testing

`Invariant.t.sol` udostępnia fuzzerowi handlery dla dozwolonych operacji, a potem sprawdza własności po losowych sekwencjach. W modelu lendingu sprawdzane są limit długu względem zabezpieczenia, custody collateral oraz to, że ekspozycja długu nie przekracza oznaczonych aktywów protokołu ponad jawną tolerancję bad debt równą zero. Model nie księguje depozytów lenderów, więc ostatni warunek jest uproszczonym testem pokrycia, nie pełnym bilansem lending poola.

To **security testing z property-based invariant testing**, a nie formal verification ani dowód poprawności. Fuzzer bada skończoną liczbę sekwencji i stanów w granicach modelu.

## Ograniczenia

Oracle i vault są minimalnymi modelami. Zakładają zaufane tokeny z 18 miejscami po przecinku, które nie pobierają opłat, nie rebazują i nie wykonują callbacków. Pomijają m.in. awarie i świeżość feedów, pełnoprecyzyjne `mulDiv`, pełną zgodność z API ERC-4626 i wiele zachowań produkcyjnych. Vault jest przykładem w stylu ERC-4626, nie implementacją całego standardu. Szczegółowe założenia, ścieżka ataku, poprawka i ograniczenia są opisane w README każdego przypadku.

## Zgłaszanie problemów i kontrybucje

Zobacz [SECURITY.md](SECURITY.md) w sprawach bezpieczeństwa oraz [CONTRIBUTING.md](CONTRIBUTING.md), aby uruchomić lokalne kontrole przed pull requestem.

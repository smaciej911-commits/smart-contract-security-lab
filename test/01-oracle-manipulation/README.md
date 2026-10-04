# 01 — Manipulacja oracle przez cenę spot

## Cel

Model lending protocol udziela pożyczek do 70% wartości zabezpieczenia. Błąd polega na tym, że wycenia collateral bieżącym stosunkiem rezerw z małego poola constant-product.

## Przebieg exploita

1. Atakujący wpłaca 1 000 tokenów collateral jako zabezpieczenie.
2. Flash loan dostarcza 1 000 000 tokenów quote.
3. Atakujący kupuje collateral z poola, podbijając chwilową cenę collateral.
4. Lending protocol odczytuje zmanipulowany spot price i pożycza 2 700 000 quote.
5. Atakujący sprzedaje kupiony collateral, przywraca cenę w przybliżeniu do wartości początkowej i spłaca flash loan.

Po manipulacji dług przewyższa 70% wartości zabezpieczenia przy cenie początkowej. Test pokazuje dodatnie saldo quote atakującego i pozostawiony dług.

## Co i dlaczego się psuje

Naruszony warunek bezpieczeństwa to `debt(user) <= collateralValue(user, trustedPrice) * LTV`. Protokół używa ceny spot, którą pożyczkobiorca może podbić w tej samej transakcji, więc sprawdzenie przechodzi dla zawyżonej wyceny. Po odwróceniu swapu cena wraca blisko poziomu bazowego, ale pożyczony dług pozostaje.

## Uruchomienie

```sh
forge test --match-path 'test/01-oracle-manipulation/Exploit.t.sol' --match-test testExploit -vvvv
```

## Poprawka i regresja

`FixedProtocol.sol` wycenia collateral przez niezależny feed, odrzuca zerową cenę i nie pozwala skonfigurować LTV poza zakresem 1–10 000 bps. Wszystkie operacje zmieniające stan są chronione przed ponownym wejściem przez callback tokena. Testy regresyjne sprawdzają odrzucenie LTV powyżej 100% oraz reentrant `transferFrom` przy spłacie: transakcja ma się wycofać bez zmiany długu ani salda protokołu. Ten mały fixture używa stałej ceny, aby izolować konkretny błąd. Produkcyjny oracle powinien mieć jawne założenia o źródłach, opóźnieniu/TWAP, świeżości danych i zachowaniu przy awarii.

Test poprawki wykonuje ten sam callback; pożyczka kończy się `InsufficientCollateral`, a cofnięcie transakcji pozostawia dług i rezerwy bez zmian.

## Invarianty

```sh
forge test --match-path 'test/01-oracle-manipulation/Invariant.t.sol' -vvvv
```

Handler losuje `deposit`, `borrow`, `repay`, `withdraw`, `liquidate` i zmianę ceny oracle na poprawionym protokole. Gdy spadek ceny narusza limit, handler w tej samej akcji wykonuje pełną likwidację pozycji, dzięki czemu invariant po każdym kroku sprawdza dług względem aktualnej ceny. Drugi invariant sprawdza, że zapisane zabezpieczenie znajduje się w kontrakcie.

Trzeci invariant sprawdza `totalDebt <= quoteBalance + wartość collateral w custody + BAD_DEBT_TOLERANCE`. Tolerancja jest jawna i wynosi zero w tym modelu. To uproszczony test pokrycia bez depozytów lenderów; nie zastępuje bilansu produkcyjnego poola.

## Dlaczego poprawka działa i ograniczenia modelu

Cena pochodząca z feedu nie zmienia się, gdy borrower wykonuje swap na poolu, więc callback nie może chwilowo podnieść limitu pożyczki. Test poprawki wykonuje tę samą ścieżkę i oczekuje `InsufficientCollateral`; regresja oraz invarianty sprawdzają, że błędna pożyczka nie przechodzi.

Pool i tokeny uproszczono dla czytelności; tokeny testowe mają dowolne mintowanie, a lokalny lender nie pobiera opłaty za flash loan. Handler invariantów mintuje quote na potrzeby likwidacji, więc ten test sprawdza przejście stanu i księgowanie długu, nie opłacalność likwidatora. Test nie twierdzi, że ten sam atak opłaci się na konkretnym rynku ani że niezależny oracle sam w sobie jest odporny na wszystkie manipulacje.

# 02 — Inflacja ceny udziału przez donation

## Co i dlaczego się psuje

Vault liczy udziały jako `assets * totalSupply / totalAssets`, zaokrąglając w dół. Wersja podatna wycenia aktywa na podstawie surowego salda tokena. Pierwszy deponent może zwiększyć `totalAssets` bez zwiększania `totalSupply`, przez co kolejny poprawny depozyt zaokrągla się do zera udziałów.

## Przebieg exploita

1. Pierwszy deponent wpłaca jedną najmniejszą jednostkę i otrzymuje jeden share.
2. Deponent bezpośrednio przesyła do vaulta `1 ether`, zmieniając `totalAssets` bez zmiany `totalSupply`.
3. Ofiara wpłaca `1 ether`; obliczenie udziałów zaokrągla wynik do zera.
4. W uproszczonym vault wpłata ofiary dochodzi do skutku mimo emisji zera udziałów.
5. Pierwszy deponent redeemuje swój share i wypłaca saldo zawierające wpłatę ofiary.

## Uruchomienie

```sh
forge test --match-path 'test/02-share-price-inflation/Exploit.t.sol' --match-test testExploit -vvvv
```

## Invariant, poprawka i regresja

`FixedProtocol.sol` dodaje wirtualne aktywa i udziały do konwersji oraz blokadę reentrancy na depozycie i redeem. Donation nie może już sprawić, że pierwsza wpłata ofiary wyemituje zero udziałów, a pierwszy deponent ponosi stratę w opisanym sekwencyjnym scenariuszu.

Regresja odtwarza ten sam ciąg: pierwszy depozyt, bezpośrednia donacja, depozyt ofiary i redeem atakującego. Po poprawce ofiara otrzymuje niezerowe udziały, a atakujący nie odzyskuje więcej aktywów niż wniósł.

```sh
forge test --match-path 'test/02-share-price-inflation/Invariant.t.sol' -vvvv
```

Handler fuzzuje wpłaty, bezpośrednie donacje i redemption. Invarianty kontrolują zgodność sumy udziałów oraz warunek `previewRedeem(totalSupply) <= totalAssets`, czyli że wykupienie wszystkich udziałów nie przekracza aktywów vaulta.

## Ograniczenia modelu

To minimalny przykład ERC-4626-style, nie pełna implementacja standardu. Kod używa zwykłego mnożenia Solidity, a nie pełnoprecyzyjnego `mulDiv`, i nie obejmuje wszystkich warunków brzegowych produkcyjnego vaulta. W prawdziwym projekcie korzystaj ze sprawdzonej implementacji ERC-4626 i osobno analizuj rounding dla każdej konwersji.

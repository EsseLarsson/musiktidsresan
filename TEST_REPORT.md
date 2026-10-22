# Testprotokoll — 2026-10-22

## Godkända kontroller

- **Produktionsbygge:** React/Vite byggde statiska filer till `dist/`. Lokal HTTP-kontroll gav status 200. Byggd med Node 20.15.1, npm 10.7.0 och Vite 6.4.5.
- **7 automatiska Node-tester:** placeringsgränser, lika år, ogiltiga positioner, samtliga år 1926–2026 över en tidslinje med dubbla år, blandning utan mutation/förlorade kort, turordning i båda lägena, komplett demoflöde till seger, felaktigt svar, slut på kort samt 200 unika ID:n med källor och matchande SQL-seed.
- **PostgreSQL 16:** schema och samtliga 200 låtar installerades i en separat lokal testdatabas. `tests/database.sql` kördes med stopp vid första fel och passerade. Testerna omfattar klassiskt/alla spelar, rättning för två spelare, korttilldelning, seger, missade svar, turbyte, dubblettanslutning, dubblettsvar, gammalt rundnummer, ogiltig/null placering, null rundnummer, spelledarbehörighet, skyddat musikkort, sena spelare, åskådare och RLS. Testdata rullades tillbaka.
- **Webbläsare:** startsidan laddade, demo startade, en placering låstes och rättades till ett poäng, nästa runda startade, en mellanplacering rättades till två poäng. Genomfört vid normal skrivbordsvy och 390 × 844 mobilvy. Horisontell rullning av tidslinjen finns för smala skärmar.
- **Beroendekontroll:** nätansluten `npm audit fix` rapporterade noll kända sårbarheter efter uppdatering till Vite 6.4.5. Detta är kontrollens resultat vid leveranstillfället, inte en framtida garanti.

## Avgränsningar

- Den lokala databasen simulerade `auth.uid()` och Supabases roller. Riktig Supabase Auth, JWT, PostgREST/RPC-transport och Realtime WebSocket testades inte. Spelsvar från två spelare testades i samma runda men ingen last- eller parallell anslutningstest utfördes.
- Ingen Supabase-projektkonfiguration, nyckel eller GitHub-repo tillhandahölls. GitHub Pages-workflow ingår men har inte körts på GitHub; appen är inte publicerad.
- Ingen uppspelning testades i Spotify. Den funktionen är en manuell instruktion och vanlig söklänk, utan API.
- Källänkar och årtalsfält finns för samtliga låtar. Det bevisar inte att alla 200 årtal överensstämmer med första utgivningen av just den inspelning som väljs i Spotify. Några stickprov har rättats manuellt; fullständig innehållsverifiering kvarstår.
- Mobilkontrollen använde en smal webbläsarvy, inte en fysisk iPhone/Android eller TV-webbläsare.

## Fel som upptäcktes och korrigerades under testerna

- Windows expanderade inte testernas jokertecken: testkommandot anger nu den konkreta testfilen och fungerar på båda plattformarna.
- En SQL-variabel krockade med aliaset i segerkontrollen. Variabeln bytte namn och hela SQL-sviten passerade därefter.
- Nullvärden i placerings-/rundargument avvisas uttryckligen, så de kan inte låsa rättningen.
- Demoläget återställer spelarvyn och respekterar valt segermål.
- Äldre Vite-versioner hade kända utvecklingsserversårbarheter; den installerade versionen uppdaterades.

## Uppföljning: riktig Supabase-tjänst ansluten

Godkänt 2026-10-22: anonym inloggning med två oberoende identiteter, rumsskapande, anslutning, start, privat musikkort, låsta svar, rättning, korrekt poäng för två spelare och avslut i både klassiskt och alla spelar. Faktiska Realtime UPDATE-händelser togs emot i båda lägena efter att PostgreSQL-prenumerationen hade bekräftats. Testet krävde en explicit WebSocket-transport för Node 20 samt väntan på prenumerationens serverkvittens. Appens webbläsarklient använder webbläsarens WebSocket och hämtar dessutom status var femte sekund. Produktionsbygget med projektets publika konfiguration passerade.

Tidigare begränsning om oprövad Supabase-transport är därmed ersatt. Fysiska enheter och GitHub-publicering är fortfarande oprövade. Testidentiteter och testspel finns kvar; inga befintliga användardata har raderats.

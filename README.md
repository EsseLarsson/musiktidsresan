# Musiktidsresan

Komplett React + Vite-projekt på svenska med GitHub Pages-workflow och Supabase SQL/backend. TV och mobiler läser samma beständiga rum via Supabase Realtime. Ingen Spotify API-integration och inga ljudfiler ingår.

## Uppdatering: Supabase anslutet

Projektet är nu konfigurerat mot din Supabase-tjänst. Två oberoende anonyma testidentiteter har spelat igenom båda lägena via riktiga API-anrop: skapa rum, ansluta, starta, hämta privat musikkort, svara, rätta, poängsätta och avsluta. Faktiska Realtime UPDATE-händelser verifierades i båda lägena. Detta ersätter den tidigare begränsningen nedan om att Supabase ännu inte testats. Testet använde separata programklienter, inte fysiska mobiler eller TV. GitHub Pages är fortfarande inte publicerat.

Den anslutna ZIP-leveransen innehåller `.env.local` med enbart den publika projektadressen och publishable-nyckeln, och `dist/` är byggd med dessa värden. Inga databaslösenord eller hemliga servernycklar ingår. Några testidentiteter och rum med spelarnamnen Anslutningstest A/B finns kvar i projektet.

## Ursprunglig leveransstatus — 22 oktober 2026

- Implementerat: rumskod, QR-inbjudan, upp till 12 spelare, separat TV-vy, privat spelledarvy, två spellägen, slumpad kortlek utan återanvändning, personliga tidslinjer, låsta placeringar, serverstyrd rättning, poäng, turordning och delad seger.
- Implementerat: anonym Supabase-inloggning, RLS, RPC med radlås, beständig spelstatus, Realtime-prenumeration samt avstämning var femte sekund och när enheten får fokus igen.
- Implementerat: lokal enspelardemo utan Supabase. Demo visar låtens titel för att du själv ska kunna spela musiken. Riktiga rum döljer det aktuella musikkortet för spelarnas API-anrop fram till rättning.
- Låtbanken har 200 verkliga låtar med källänkar, från 1926 till 2026. **Alla 200 årtal är inte manuellt verifierade mot originalinspelningen.** Se `SOURCES.md` och varje posts `verification`. Detta kvarstår innan banken kan kallas fullständigt verifierad.
- Testat: produktionsbygge, sju automatiska regel-/datatester, lokala PostgreSQL-integrationstester för båda lägena, behörigheter och poäng, samt två demo-rundor i webbläsare och mobilvy 390 × 844.
- Inte testat: en driftsatt Supabase-tjänst, dess Auth/Realtime via WebSocket mellan fysiska enheter, GitHub Actions-publicering eller Spotify-uppspelning. Inga anslutningsuppgifter eller GitHub-repo fanns tillgängliga. Därför är projektet inte publicerat.

Tidigare ChatGPT-historik gick endast att hämta som referensmarkörer och den länkade Work-chatten kunde inte läsas. Inga befintliga projektfiler hittades. Specifikation och regler nedan bygger därför på beställningen i den här chatten; de är inte påstått återställda tidigare beslut.

## Kör direkt lokalt

Kräver Node.js 22 LTS (bygget har även testats med Node 20.15.1).

```sh
npm ci
npm test
npm run dev
```

Öppna adressen som visas och välj **Prova själv utan konto eller server**. Förhandsbyggd demo ligger också i `dist/`; servera den via en vanlig webbserver, öppna inte HTML-filen direkt med `file://`.

```sh
npm run build
npm run preview
```

## Konfigurera Supabase

1. Skapa ett Supabase-projekt. Aktivera **Anonymous Sign-Ins** under Authentication enligt [Supabase-dokumentationen](https://supabase.com/docs/guides/auth/auth-anonymous). Spelare får en anonym identitet utan e-post eller lösenord. En ny webbläsare/inkognito är en ny identitet.
2. Kör `supabase/schema.sql` en gång i ett nytt projekts SQL Editor. Kör därefter `supabase/seed.sql`. Schemafilen skapar tabeller, RLS, funktioner, rättningstrigger och lägger till `rooms` i publikationen `supabase_realtime`. Kör aldrig `tests/bootstrap.sql` i Supabase; den är endast en lokal testsimulering av Auth.
3. Kontrollera att `rooms` är aktiverad för Realtime. Se [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).
4. Kopiera `.env.example` till `.env.local`. Fyll i projektets URL och **publika anon-nyckel**. Använd aldrig `service_role` eller en hemlig nyckel i Vite. Starta om utvecklingsservern efter ändringar.
5. Kör appen och skapa ett rum. Anslut TV och minst två spelare via den publicerade HTTPS-adressen för ett riktigt enhetstest.

Supabase-nyckeln hamnar avsiktligt i den statiska frontendkoden. Behörigheterna skyddas av Auth, RLS och serverfunktionerna. `room_secrets` är oläsbar för klienten och aktuellt kort kan endast hämtas av spelledaren. Låtbanken levereras även som JSON för demo och är därför känd information; detta är ett sällskapsspel och inget system för fuskfri tävling. Spelledaren känner till facit och bör helst inte tävla.

Rumskoden ger behörighet att gå med och läsa rummet som åskådare. Dela därför koden med deltagarna. Spelarnamn och poäng visas för alla i rummet. Spelledarens identitet finns i webbläsarens lagrade Supabase-session: dela ingen sådan session. Den som rensar sin webbläsardata kan inte återta sin spelare/spelledarroll. Behåll samma origin och webbläsare för återanslutning.

## Publicera på GitHub Pages

1. Lägg projektmappens **innehåll** i roten av ett GitHub-repository, inklusive `.github/workflows/pages.yml`, och använd grenen `main`.
2. Skapa repository-secrets `VITE_SUPABASE_URL` och `VITE_SUPABASE_ANON_KEY` under Settings → Secrets and variables → Actions.
3. Välj Settings → Pages → Source: **GitHub Actions**. Push till `main` kör tester, bygger `dist` och publicerar. Se [GitHubs arbetsflödesguide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
4. Workflow sätter basvägen till `/<repository-namn>/`. För ett repo som heter `användare.github.io` eller en egen domän: ändra `VITE_BASE_PATH` i workflow till `/`. Se [Vites anvisningar](https://vite.dev/guide/static-deploy.html).
5. Öppna den URL som GitHub visar. QR-koden bygger på den aktuella sidans origin och sökväg, så den fungerar även i en repository-undermapp. Inga klientrouter-sökvägar används, endast frågeparametrar.

Secrets läses vid bygget. Ändrade secrets kräver en ny workflow-körning. Saknas värden fungerar demon, men riktiga rum visar ett konfigurationsfel. ZIP-filens `dist/` är byggd utan Supabase-värden och är därför en demo; bygg om för din miljö.

## Så arrangerar ni ett spel

1. Spelledaren öppnar appen på en egen enhet och skapar ett rum. Välj läge och segermål (3, 5 eller 10 rätt). Spelledaren är åskådare tills hen väljer **Lägg till mig**.
2. Öppna **separat TV-vy** på stor skärm, eller använd rummets URL med `&view=tv`. TV-vyn ansluter som åskådare utan att ta en spelarplats. Den visar QR-kod i lobbyn och alla tidslinjer under spelet. Den kan inte hämta musikkort från ett annat användarkonto.
3. Spelarna skannar QR-koden, anger namn och ansluter på sina mobiler före start. Flera flikar i samma webbläsarprofil delar identitet; använd olika enheter/profiler när du testar flera spelare.
4. Spelledaren startar, visar musikkortet **privat** och använder en separat mobil med Spotify Premium för att manuellt söka och spela rätt version. Musikkortet kan öppna en vanlig Spotify-sökning. Ingen API-anslutning, token, ljudsynk eller automatisk uppspelning används. Dölj musikmobilens skärm för deltagarna.
5. Placera den okända låten i en lucka på tidslinjen och lås svaret. Spelledaren klickar **Rätta rundan**, därefter **Nästa låt / visa vinnare**.

Behöver du både TV och privat spelledarkontroll: skapa rummet på spelledarens enhet och anslut TV:n som åskådare. `TV-läge` på spelledarens egen sida döljer kontrollerna men är ingen säkerhetsgräns för någon som redan äger spelledarens session.

## De valda spelreglerna

- Varje spelare får ett slumpat, synligt startkort. Det ger noll poäng.
- Klassiskt: en spelare per runda; turen går runt även efter en miss.
- Alla spelar: samma hemliga låt, men var och en svarar på sin personliga tidslinje.
- Ett svar är rätt när föregående år ≤ låtens år ≤ följande år. Vid samma år godkänns alla angränsande platser som bevarar ordningen.
- Rätt svar ger ett poäng och ett nytt kort. Fel eller uteblivet svar ger noll poäng och inget kort. Inga minuspoäng, bonuspoäng eller stölder.
- Svar går inte att ändra efter låsning. Rättningen sker först när spelledaren väljer den. Spelledaren kan rätta innan alla svarat; de obesvarade får då en miss.
- Första avslutade rundan där någon når målet avslutar spelet när spelledaren går vidare. Högst poäng vinner; lika poäng ger delad seger. Tom kortlek avslutar också spelet.
- Inga dubbla låtar i samma kortlek. Slumpningen är jämn över låtar, inte över årtionden. Alla årtal mellan 1926 och 2026 behöver inte finnas representerade.

## Teknik och filer

`src/main.jsx`: svenska gränssnittet och vyerna. `src/backend.js`: Supabase Auth, RPC och Realtime med återhämtning. `src/engine.js`: regler för lokal demo och tester. `src/songs.json`: 200 låtar och källor. `src/styles.css`: responsiv design. `supabase/schema.sql`: auktoritativa spelregler och databasbehörigheter. `supabase/seed.sql`: samma låtbank på servern. `SOURCES.md`: katalog och verifieringsbegränsningar. `TEST_REPORT.md`: utförda kontroller.

Alla serverändringar går via RPC och låser rummets databasrad. Det gör att rättning och sena svar inte kan skriva över varandras spelstatus. Ett inskickat svar innehåller rundnummer; dubbletter och svar från äldre rundor avvisas. Realtime-meddelanden triggar en ny läsning av den beständiga statusen, så en missad händelse kräver ingen återspelning.

## Tester

```sh
npm test
npm run build
```

Lokala SQL-tester kräver PostgreSQL och en **ny, tom testdatabas** som ägs av testanvändaren:

```sh
psql -v ON_ERROR_STOP=1 -d DIN_TOMMA_TESTDATABAS -f tests/bootstrap.sql -f supabase/schema.sql -f supabase/seed.sql -f tests/database.sql
```

Testdatabasen behöver kunna skapa roller och en publication. `bootstrap.sql` skapar testrollerna `anon`, `authenticated` och ett minimalt `auth.uid()`; den installerar inte Supabase Auth eller Realtime. Därför bevisar detta databasspelregler och RLS, men inte WebSocket-transport eller verkliga JWT-sessioner. `tests/database.sql` rullar tillbaka sina egna testdata.

Efter publicering, testa båda spellägena med TV och två mobiler, rätt/fel/uteblivet svar, dubbelt knapptryck, samma år, omladdning av spelledaren, bakgrund/återgång på mobil samt nätavbrott. Kontrollera att musikkortet inte visas på TV innan rättning.

## Drift, kända begränsningar och underhåll

- Ingen överlåtelse av spelledarroll, spelarutkastning, byte av regler efter start, timer eller kontoregistrering. Skapa ett nytt rum för att spela igen. En frånkopplad spelare ligger kvar; spelledaren kan rätta utan dennes svar.
- Rummen sparas tills de tas bort. Nya anslutningar avvisas om senaste spelaktiviteten är äldre än 24 timmar. En ägare kan rensa gamla rum i SQL Editor med underhållsfrågan längst ned i schemafilen; relaterade medlemskap och kortlekar raderas då också.
- För öppen publik trafik behövs vidare skydd mot masskapade anonyma konton/rum och en lämplig driftbudget. Projektet är avsett för privata spelomgångar; det innehåller ingen automatisk CAPTCHA-hantering eller missbruksadministration.
- Google Fonts används för valfri typografi; systemtypsnitt fungerar om nätet blockerar dem.
- Uppdatera **både** `src/songs.json` och `supabase/seed.sql` vid låtändringar och starta nya rum. Befintliga tidslinjer har kopierad metadata. Blanda inte olika katalogversioner mitt i en spelomgång.
- Kontrollera den spelade inspelningen mot källan. Nyinspelningar, liveversioner, covers och remasters kan ge olika årtal. Om ni upptäcker fel: rätta banken före nästa spel; ingen manuell poängjustering finns i gränssnittet.

## Licens

Nyskriven projektkod är MIT-licensierad, se `LICENSE`. Wikidata-metadata är CC0. Externa tjänster, musik och typsnitt omfattas av respektive rättigheter och villkor. Inga rättigheter till musik eller Spotify-innehåll upplåts genom projektet.


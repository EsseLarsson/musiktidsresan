# Avslutning, närvaro och automatisk städning

Den här uppdateringen ersätter README:s äldre uppgifter om att avslutning, spelarutkastning och automatisk städning saknas.

## Aktivering på ett befintligt projekt

1. Kör `supabase/migrations/002_room_lifecycle.sql` i Supabase SQL Editor. Kör **inte** grundfilen `schema.sql` igen på en befintlig databas.
2. Kör `supabase/003_schedule_cleanup.sql` för att aktivera timvis städning. Den sista frågan ska visa jobbet `musiktidsresan-cleanup` med `active = true`.
3. Publicera frontend via GitHub Actions och ladda om appen. Innan databasen är uppdaterad fungerar befintliga spel vidare och appen visar att de nya rumsfunktionerna väntar på databasuppdateringen.

Vid en nyinstallation är ordningen schema.sql → seed.sql → 002_room_lifecycle.sql → 003_schedule_cleanup.sql. Migrationen kan köras om. Den raderar inga rum eller användare när den installeras. Städjobbet börjar arbeta vid nästa schemalagda körning. Aktivering i produktionsdatabasen är en separat åtgärd och är inte bekräftad enbart för att filerna finns på GitHub.

## Beteende

- Spelledaren får **Avsluta rum**, med bekräftelse. Det stänger rummet för spel och återanslutning och visar en avslutningssida för deltagarna. Rummets data behålls i 24 timmar före städning.
- Spelare får **Lämna rum**, med bekräftelse. Spelledaren kan **Ta bort** andra spelare. Detta är bestående för samma identitet i det rummet. En borttagen spelare kan inte återansluta som åskådare eller lämna fler svar. Vid ett frivilligt tillfälligt avbrott ska spelaren i stället behålla sin webbläsarsession och komma tillbaka.
- Tillfälliga nätavbrott eller stängda flikar avslutar inte rummet. Appen skickar livstecken var 30:e sekund. Ingen kontakt under 90 sekunder visas som **Frånkopplad**; vyn uppdateras normalt inom ytterligare fem sekunder. Det är en uppskattning: mobilers strömsparläge kan pausa livstecken.
- Om spelledaren försvinner visas information om det. Ingen automatisk överlåtelse av spelledarroll sker.
- I klassiskt läge hoppas borttagna spelare över. Återstående spelare behåller sina kort och poäng. Borttagna spelare visas inte i ställningen. En tom spelarlista efter borttagning stänger rummet.
- Aktiva spelares och spelledarens livstecken håller pågående rum vid liv. Enbart åskådare eller öppna slutresultat håller inte rum vid liv. Redan utgångna rum återupplivas inte.
- Varje timme raderas rum som inte haft spelaktivitet/livstecken från spelledare eller spelare på 24 timmar. Då försvinner även medlemskap och privat kortlek. Faktisk radering sker alltså efter cirka 24–25 timmar.
- Samma städjobb tar bort gamla anonyma **spelidentiteter** efter sju dagars inaktivitet, men endast om de inte hör till något sparat rum eller medlemskap. Permanenta konton och anonyma konton som inte registrerats av spelet berörs inte. Redan existerande rum/medlemskap registreras vid migrationen med nytt tidsvärde för att ge en sjudagarsfrist.
- Startsidan skapar inte längre ett nytt anonymt konto vid varje första besök. Kontot skapas först vid anslutning eller rumsskapande (TV-inbjudningar ansluter automatiskt).

Närvaron omfattar anslutningen till spelet, inte om Spotify spelar ljud. Flera flikar delar identitet; en öppen flik kan därför hålla en spelare ansluten. Det går inte att garantera permanent utkastning av en person som byter anonym identitet; rumskoden är fortfarande inbjudan.

## Tester och kontroll

Åtta Node-tester och produktionsbygget passerar. `tests/database.sql` passerar även efter migrationen. `tests/lifecycle.sql` testar avslutnings-/borttagningsbehörighet, offlinegräns, turordning, utgångna rum, återanslutningsskydd, kaskadradering och skydd för permanenta, orelaterade och rumskopplade konton. Migrationen kördes två gånger lokalt för att kontrollera återkörning.

Lokala PostgreSQL-tester bevisar inte att pg_cron är aktiverat i ditt Supabase-projekt. Kontrollera `cron.job` efter aktivering. Se körningar/fel under Supabase Cron eller `cron.job_run_details`. Slutlig kontroll i riktig Supabase och med mobiler behövs efter installationen.

Källor: [Supabase Cron](https://supabase.com/docs/guides/cron), [schemaläggning](https://supabase.com/docs/guides/cron/quickstart), [anonyma användare och städning](https://supabase.com/docs/guides/auth/auth-anonymous).

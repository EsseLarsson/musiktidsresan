import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {correct,shuffle,eligible,demoStart,demoSubmit,demoNext} from '../src/engine.js';
const songs=JSON.parse(fs.readFileSync(new URL('../src/songs.json',import.meta.url)));
test('placement boundaries, equal years and invalid positions',()=>{
 const t=[{year:1960},{year:1980},{year:2000}];
 assert.equal(correct(1950,t,0),true);assert.equal(correct(1970,t,1),true);assert.equal(correct(2026,t,3),true);
 assert.equal(correct(1980,t,1),true);assert.equal(correct(1980,t,2),true);
 for(const pos of [-1,4,1.5,null])assert.equal(correct(1970,t,pos),false);
 assert.equal(correct(1970,t,2),false);assert.equal(correct(1926,[],0),true);
});
test('all legal insertion positions preserve nondecreasing years',()=>{
 for(let y=1926;y<=2026;y++)for(let i=0;i<=4;i++){
  const t=[1940,1970,1970,2000].map(year=>({year}));
  const inserted=[...t];inserted.splice(i,0,{year:y});
  assert.equal(correct(y,t,i),inserted.every((s,j)=>j===0||inserted[j-1].year<=s.year));
 }
});
test('shuffle is a permutation, does not mutate, and seed controls result',()=>{
 const original=[1,2,3,4,5],result=shuffle(original,()=>0);
 assert.deepEqual(original,[1,2,3,4,5]);assert.deepEqual([...result].sort(),original);assert.notDeepEqual(result,original);
});
test('classic turn and all-player eligibility',()=>{
 const s={phase:'guess',mode:'classic',turn:3,players:[{id:'a'},{id:'b'}]};
 assert.equal(eligible(s,'a'),false);assert.equal(eligible(s,'b'),true);
 assert.equal(eligible({...s,mode:'all'},'a'),true);assert.equal(eligible({...s,phase:'reveal'},'b'),false);
});
test('removed players cannot guess in either mode',()=>{
 const s={phase:'guess',mode:'all',turn:0,players:[{id:'a',removed:true},{id:'b'}]};
 assert.equal(eligible(s,'a'),false);assert.equal(eligible(s,'b'),true);
 assert.equal(eligible({...s,mode:'classic'},'a'),false);
});
test('complete demo, no reused songs, victory and immutable scoring',()=>{
 let s=demoStart(songs),seen=new Set(s.players[0].timeline.map(t=>t.id));s.target=3;
 for(let round=1;round<=3;round++){
  assert.ok(!seen.has(s.current.id));seen.add(s.current.id);
  const pos=Array.from({length:s.players[0].timeline.length+1},(_,i)=>i).find(i=>correct(s.current.year,s.players[0].timeline,i));
  const next=demoSubmit(s,pos);assert.equal(s.players[0].score,round-1);assert.equal(next.players[0].score,round);
  s=demoNext(next);
 }
 assert.equal(s.phase,'finished');assert.equal(s.players[0].timeline.length,4);
});
test('wrong demo guess gives no card or point; exhausted deck ends game',()=>{
 const s=demoStart(songs);s.current.year=2026;s.players[0].timeline=[{year:1926}];
 const n=demoSubmit(s,0);assert.equal(n.players[0].score,0);assert.equal(n.players[0].timeline.length,1);
 assert.equal(demoNext({...n,deck:[]}).phase,'finished');
});
test('dataset is 200 distinct sourced songs covering 1926–2026; SQL seed matches',()=>{
 assert.equal(songs.length,200);assert.equal(new Set(songs.map(s=>s.id)).size,200);
 assert.equal(Math.min(...songs.map(s=>s.year)),1926);assert.equal(Math.max(...songs.map(s=>s.year)),2026);
 for(const s of songs){assert.ok(s.title&&s.artist&&s.source.startsWith('https://'));assert.ok(Number.isInteger(s.year)&&s.year>=1926&&s.year<=2026);}
 const sql=fs.readFileSync(new URL('../supabase/seed.sql',import.meta.url),'utf8');
 for(const s of songs)assert.ok(sql.includes(`(${s.id},`));
});

// DEV-only visual fixture: no accounts, rooms or network writes.
import songs from '../src/songs.json';
export default {code:'TVTEST',host_id:'fixture-host',state:{mode:'all',phase:'guess',target:9,round:7,turn:0,answers:{},players:Array.from({length:4},(_,i)=>({id:'fixture-'+i,name:['Alex','Kim','Sam','Robin'][i],score:i+3,timeline:songs.slice(i*10,i*10+10)}))}};

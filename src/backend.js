import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL, key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const db=url&&key?createClient(url,key):null;
export async function login(){if(!db)throw Error('Supabase är inte konfigurerat. Använd demo eller följ README.'); const {data:{session}}=await db.auth.getSession(); if(session)return session.user.id; const {data,error}=await db.auth.signInAnonymously();if(error)throw error;return data.user.id;}
export async function action(name,args){const {data,error}=await db.rpc(name,args);if(error)throw error;return data;}
export function watch(code,onState,onStatus,onPresence=()=>{},onFeatures=()=>{},onEnded=()=>{}){
  let alive=true;
  let features=true;
  const heartbeat=async()=>{const {error}=await db.rpc('room_heartbeat',{p_code:code});if(!alive)return;
    if(error?.code==='PGRST202'){features=false;onFeatures(false);return;}
    if(error?.code==='P0001'){onEnded(error.message);return;}
    if(!error){features=true;onFeatures(true);}
  };
  const refresh=async()=>{const {data,error}=await db.from('rooms').select('*').eq('code',code).maybeSingle();if(!alive)return;if(data)onState(data);else if(!error){onEnded('Rummet finns inte längre eller du har lämnat/tagits bort.');return;}if(error)onStatus('Kunde inte hämta rummet. Försöker igen…');
    if(features){const {data:presence}=await db.rpc('room_presence',{p_code:code});if(alive&&presence)onPresence(presence);}
  };
  const channel=db.channel('room:'+code).on('postgres_changes',{event:'UPDATE',schema:'public',table:'rooms',filter:`code=eq.${code}`},refresh).subscribe(status=>{if(alive)onStatus(status==='SUBSCRIBED'?'Ansluten':'Ansluter / återansluter…');if(status==='SUBSCRIBED')refresh();});
  heartbeat();refresh(); const poll=setInterval(refresh,5000),pulse=setInterval(heartbeat,30000);
  const focus=()=>{heartbeat();refresh();};window.addEventListener('focus',focus);
  return ()=>{alive=false;clearInterval(poll);clearInterval(pulse);window.removeEventListener('focus',focus);db.removeChannel(channel);};
}

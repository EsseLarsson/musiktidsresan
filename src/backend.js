import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL, key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const db=url&&key?createClient(url,key):null;
export async function login(){if(!db)throw Error('Supabase är inte konfigurerat. Använd demo eller följ README.'); const {data:{session}}=await db.auth.getSession(); if(session)return session.user.id; const {data,error}=await db.auth.signInAnonymously();if(error)throw error;return data.user.id;}
export async function action(name,args){const {data,error}=await db.rpc(name,args);if(error)throw error;return data;}
export function watch(code,onState,onStatus){
  let alive=true;
  const refresh=async()=>{const {data,error}=await db.from('rooms').select('*').eq('code',code).single();if(alive&&data)onState(data);if(error&&alive)onStatus('Kunde inte hämta rummet. Försöker igen…');};
  const channel=db.channel('room:'+code).on('postgres_changes',{event:'UPDATE',schema:'public',table:'rooms',filter:`code=eq.${code}`},refresh).subscribe(status=>{if(alive)onStatus(status==='SUBSCRIBED'?'Ansluten':'Ansluter / återansluter…');if(status==='SUBSCRIBED')refresh();});
  refresh(); const poll=setInterval(refresh,5000);
  const focus=()=>refresh();window.addEventListener('focus',focus);
  return ()=>{alive=false;clearInterval(poll);window.removeEventListener('focus',focus);db.removeChannel(channel);};
}

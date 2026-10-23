export function trackLink(input){
 try{const u=new URL(input.trim());const m=u.pathname.match(/^\/(?:intl-[a-z]{2}\/)?track\/([a-zA-Z0-9]{22})\/?$/);return u.protocol==='https:'&&u.hostname==='open.spotify.com'&&m?`https://open.spotify.com/track/${m[1]}`:null;}catch{return null;}
}

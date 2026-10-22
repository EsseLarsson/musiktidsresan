export function correct(year, timeline, position) {
  return Number.isInteger(position) && position >= 0 && position <= timeline.length &&
    (position === 0 || timeline[position-1].year <= year) &&
    (position === timeline.length || year <= timeline[position].year);
}
export function shuffle(items, random = Math.random) {
  const result = [...items];
  for(let i=result.length-1;i>0;i--){const j=Math.floor(random()*(i+1)); [result[i],result[j]]=[result[j],result[i]];}
  return result;
}
export function eligible(state, playerId) {
  return state.phase === 'guess' && state.players.some(p=>p.id===playerId&&!p.removed) && (state.mode === 'all' || state.players[state.turn % state.players.length]?.id === playerId);
}
export function demoStart(songs, mode='all') {
  const deck=shuffle(songs);
  return {phase:'guess',mode,round:1,turn:0,target:5,current:deck.pop(),deck,answers:{},players:[{id:'demo',name:'Du',score:0,timeline:[deck.pop()]}]};
}
export function demoSubmit(state,position) {
  const next=structuredClone(state); const p=next.players[0];
  const ok=correct(next.current.year,p.timeline,position);
  next.answers.demo={position,correct:ok}; if(ok){p.timeline.splice(position,0,next.current);p.score++;}
  next.phase='reveal';return next;
}
export function demoNext(state) {
  if(state.players.some(p=>p.score>=state.target)||!state.deck.length)return {...state,phase:'finished'};
  const next=structuredClone(state); next.current=next.deck.pop();next.answers={};next.phase='guess';next.round++;return next;
}

// ======================= MOD: NEXT BEST MOVE ADVISOR ("Hex Helper") =======================
// Keys (during your turn):  H = show/hide   N = play the next step of the plan
//                           A = auto-play the plan   E = end turn   M = normal/aggressive mode
// Aggressive mode picks the enemy nation that is cheapest to wipe out and plays to take its capital.
// It works out whether one army can win there or several attacks in a row can wear the garrison down.
//
// How it thinks:
//  * Copies the board into a lightweight model and re-implements the game's own rules on it
//    (movement incl. ports/sea, combat, annexing, morale gains/losses, nation elimination,
//    province liberation, end-of-turn morale decay and unit spawning).
//  * Beam-searches whole turns (up to 5 moves) on that model, so it plans move sequences
//    rather than one move at a time.
//  * Scores the position at the end of the turn, after your units spawn: troops, morale,
//    income (towns/ports/land), what the enemies can take from you on their turn, what you
//    can strike next turn, and how close your armies are to targets (real path distance over
//    land and sea via ports).
//  * Then replays the enemies' next turn with a port of the game's own AI (it reproduces the real
//    AI's whole turn exactly in tests) for the best 16 plans, and picks the plan that leaves you
//    strongest after they reply. The panel shows those predicted replies.
//  * Also decides when to give your one speech (+50 morale to every army) and which nation to sign
//    your one pact with; both show up as plan steps.
//  * Tested offline against the real AI (see test/README.md): on Hard about 84% wins in normal mode
//    and 87% in aggressive (the game's own AI in your seat wins none); on Medium 94-96%.
//  * The copy of the enemy AI reproduces the real one exactly, including how Flash's Array.sort breaks
//    ties (measured from the real player, see test/sorttest).
_global.HWA_W = {rerank:16,threat2:0.3,opp2:0.6,mix:0,beam:5,cand:16,maxcand:20,enemy:0.7,enemyMor:1.2,myMor:0.6,inc:6,enInc:1.5,elim:300,threat:0.35,opp:0.3,stratG:0.4,stratC:0.2,gang:0,siege:200,stratT:0.6,tgtEnemy:1.15,qT:3,aggThreat:0.35,confT:15,autoSpeed:1,speechHold:0.3,speechUse:1,pactHold:40,pactUse:1,ply2:0,ply2Moves:5,aggThreat2:0.3,aggOpp2:0.6,aggElim:300,aggSpeechHold:0.3,tgtDef:1.5,tgtPow:0.3,tgtDist:6,tgtStick:0.75,aggOther:1,sigPart:0.45,t2:0,t2Bias:4,capGang:0};
_global.HWA_TIME = 6000;
// automatic speed adjustment: search sizes from small to large; starts at the tuned default (3)
_global.HWA_LEVELS = [{beam:2,cand:4,maxcand:6,rerank:4},{beam:3,cand:6,maxcand:10,rerank:8},{beam:4,cand:10,maxcand:14,rerank:12},{beam:5,cand:16,maxcand:20,rerank:16},{beam:8,cand:16,maxcand:22,rerank:24}];
_global.HWA_SLOW = 3000;
_global.HWA_FAST = 800;
_global.hwaSetLevel = function(lv)
{
   if(lv < 0)
   {
      lv = 0;
   }
   if(lv >= HWA_LEVELS.length)
   {
      lv = HWA_LEVELS.length - 1;
   }
   hwa.level = lv;
   var L = HWA_LEVELS[lv];
   HWA_W.beam = L.beam;
   HWA_W.cand = L.cand;
   HWA_W.maxcand = L.maxcand;
   HWA_W.rerank = L.rerank;
};
_global.hwaFieldName = function(f)
{
   if(f.estate == "town" || f.estate == "port")
   {
      return f.town_name;
   }
   return (f.type == "water" ? "sea " : "field ") + f.fx + "," + f.fy;
};
_global.hwaPartyColor = function(B, p)
{
   var c = B.hw_parties_colors[p].toString(16);
   while(c.length < 6)
   {
      c = "0" + c;
   }
   return "#" + c;
};
_global.hwaBuildStatic = function(B)
{
   var S = new Object();
   S.board = B;
   S.X = B.hw_xmax;
   S.Y = B.hw_ymax;
   S.P = B.hw_parties_count;
   S.human = B.human;
   S.names = B.hw_parties_names;
   var n = S.X * S.Y;
   S.n = n;
   S.typ = new Array(n);
   S.est = new Array(n);
   S.cap = new Array(n);
   S.nb = new Array(n);
   S.fld = new Array(n);
   var x = 0;
   var y;
   var f;
   var i;
   while(x < S.X)
   {
      y = 0;
      while(y < S.Y)
      {
         f = getField(x,y,B);
         i = x * S.Y + y;
         f.hwa_i = i;
         S.fld[i] = f;
         S.typ[i] = f.type != "land" ? 0 : 1;
         S.est[i] = f.estate != "town" ? (f.estate != "port" ? 0 : 2) : 1;
         S.cap[i] = f.capital;
         y++;
      }
      x++;
   }
   i = 0;
   var a;
   var k;
   while(i < n)
   {
      a = new Array(6);
      k = 0;
      while(k < 6)
      {
         a[k] = !S.fld[i].neighbours[k] ? -1 : S.fld[i].neighbours[k].hwa_i;
         k++;
      }
      S.nb[i] = a;
      i++;
   }
   S.capF = new Array(S.P);
   var p = 0;
   while(p < S.P)
   {
      S.capF[p] = B.hw_parties_capitals[p].hwa_i;
      p++;
   }
   // data the game's own AI uses: distance-to-capital tables, "near a town" flags, 2-ring neighbourhoods
   S.fx = new Array(n);
   S.fy = new Array(n);
   S.prof = new Array(n);
   S.ntown = new Array(n);
   S.ring = new Array(n);
   var ringF;
   i = 0;
   while(i < n)
   {
      f = S.fld[i];
      S.fx[i] = f.fx;
      S.fy[i] = f.fy;
      S.prof[i] = !f.profitability ? new Array() : f.profitability.slice();
      S.ntown[i] = !f.n_town ? 0 : 1;
      a = new Array();
      ringF = getFurtherNeighbours(f);
      k = 0;
      while(k < ringF.length)
      {
         if(ringF[k])
         {
            a.push(ringF[k].hwa_i);
         }
         k++;
      }
      S.ring[i] = a;
      i++;
   }
   hwa.S = S;
   hwa.mark = new Array(n);
   hwa.stamp = 0;
};
_global.hwaRootState = function(B)
{
   var S = hwa.S;
   var n = S.n;
   var st = new Object();
   st.ow = new Array(n);
   st.ap = new Array(n);
   st.ac = new Array(n);
   st.am = new Array(n);
   st.mv = new Array(n);
   st.peace = B.hw_peace;
   st.win = false;
   st.el = 0;
   st.moves = new Array();
   st.left = B.move_points;
   st.speech = !B.hw_parties_speech_given[S.human] && HWA_W.speechUse ? 1 : 0;
   st.pact = !B.hw_pact_signed && B.human_condition <= 1 && HWA_W.pactUse ? 1 : 0;
   var i = 0;
   var f;
   var a;
   var movable = 0;
   while(i < n)
   {
      f = S.fld[i];
      st.ow[i] = f.party;
      a = f.army;
      if(a && a.remove_time < 0)
      {
         st.ap[i] = a.party;
         st.ac[i] = a.count;
         st.am[i] = a.morale;
         st.mv[i] = !a.moved ? 0 : 1;
         if(a.party == S.human && !a.moved)
         {
            movable++;
         }
      }
      else
      {
         st.ap[i] = -1;
         st.ac[i] = 0;
         st.am[i] = 0;
         st.mv[i] = 0;
      }
      i++;
   }
   if(st.left > movable)
   {
      st.left = movable;
   }
   var q = 0;
   while(q < S.P)
   {
      if(st.ow[S.capF[q]] != q)
      {
         st.el |= 1 << q;
      }
      q++;
   }
   return st;
};
_global.hwaClone = function(st)
{
   var c = new Object();
   c.ow = st.ow.slice();
   c.ap = st.ap.slice();
   c.ac = st.ac.slice();
   c.am = st.am.slice();
   c.mv = st.mv.slice();
   c.peace = st.peace;
   c.win = st.win;
   c.el = st.el;
   c.moves = st.moves.slice();
   c.left = st.left;
   c.speech = st.speech;
   c.pact = st.pact;
   return c;
};
_global.hwaMoraleAll = function(st, p, x)
{
   if(x == 0 || p < 0)
   {
      return undefined;
   }
   var ap = st.ap;
   var ac = st.ac;
   var am = st.am;
   var n = hwa.S.n;
   var i = 0;
   var v;
   while(i < n)
   {
      if(ap[i] == p)
      {
         v = am[i] + x;
         if(v < 0)
         {
            v = 0;
         }
         if(v > ac[i])
         {
            v = ac[i];
         }
         am[i] = v;
      }
      i++;
   }
};
_global.hwaAddMorale = function(st, i, x)
{
   var v = st.am[i] + x;
   if(v < 0)
   {
      v = 0;
   }
   if(v > st.ac[i])
   {
      v = st.ac[i];
   }
   st.am[i] = v;
};
_global.hwaArmyCount = function(st, p)
{
   var c = 0;
   var i = 0;
   var n = hwa.S.n;
   while(i < n)
   {
      if(st.ap[i] == p)
      {
         c++;
      }
      i++;
   }
   return c;
};
_global.hwaProvinces = function(st, p)
{
   // conquered capitals whose nation has no armies left (the game's win counter)
   var S = hwa.S;
   var c = 0;
   var q = 0;
   while(q < S.P)
   {
      if(q != p && st.ow[S.capF[q]] == p && hwaArmyCount(st,q) == 0)
      {
         c++;
      }
      q++;
   }
   return c;
};
_global.hwaReach = function(st, s)
{
   // same fields as the game's getPossibleMoves(field, true, false)
   var S = hwa.S;
   var nb = S.nb;
   var typ = S.typ;
   var est = S.est;
   var ap = st.ap;
   var ac = st.ac;
   var p = ap[s];
   var out = new Array();
   var mark = hwa.mark;
   var stamp = ++hwa.stamp;
   var isPort = est[s] == 2;
   var isSea = typ[s] == 0;
   var ns = nb[s];
   var k = 0;
   var n1;
   var nn;
   var kk;
   var ns2;
   var mode;
   while(k < 6)
   {
      n1 = ns[k];
      if(n1 >= 0 && (isPort || isSea || typ[n1] == 1) && (ap[n1] < 0 || ap[n1] != p || typ[n1] == 1 && ac[n1] < 99))
      {
         if(mark[n1] != stamp)
         {
            mark[n1] = stamp;
            out.push(n1);
         }
         if(ap[n1] < 0)
         {
            mode = 0;
            if(typ[n1] == 0)
            {
               mode = !isSea ? (!isPort ? 0 : 1) : 3;
            }
            else if(est[n1] == 0 && !isSea)
            {
               mode = 2;
            }
            if(mode)
            {
               ns2 = nb[n1];
               kk = 0;
               while(kk < 6)
               {
                  nn = ns2[kk];
                  if(nn >= 0 && nn != s && mark[nn] != stamp && (mode == 3 || (mode != 1 ? typ[nn] == 1 : typ[nn] == 0)) && (ap[nn] < 0 || ap[nn] != p || typ[nn] == 1 && ac[nn] < 99))
                  {
                     mark[nn] = stamp;
                     out.push(nn);
                  }
                  kk++;
               }
            }
         }
      }
      k++;
   }
   return out;
};
_global.hwaUpdate = function(st)
{
   // eliminations + the morale floor, as in updateBoard
   var S = hwa.S;
   var n = S.n;
   var P = S.P;
   var ap = st.ap;
   var ac = st.ac;
   var am = st.am;
   var ow = st.ow;
   var q = 0;
   var w;
   var i;
   while(q < P)
   {
      w = ow[S.capF[q]];
      if(w != q)
      {
         if(!(st.el & 1 << q))
         {
            st.el |= 1 << q;
            i = 0;
            while(i < n)
            {
               if(ap[i] == q)
               {
                  ap[i] = -1;
                  ac[i] = 0;
                  am[i] = 0;
                  st.mv[i] = 0;
               }
               if(ow[i] == q)
               {
                  ow[i] = w;
               }
               i++;
            }
         }
      }
      else if(st.el & 1 << q)
      {
         st.el ^= 1 << q;
      }
      q++;
   }
   var tot = new Array(0,0,0,0,0,0,0,0);
   i = 0;
   while(i < n)
   {
      if(ap[i] >= 0)
      {
         tot[ap[i]] += ac[i];
      }
      i++;
   }
   i = 0;
   var fl;
   while(i < n)
   {
      if(ap[i] >= 0)
      {
         fl = Math.floor(tot[ap[i]] / 50);
         if(am[i] < fl)
         {
            am[i] = fl <= ac[i] ? fl : ac[i];
         }
      }
      i++;
   }
};
_global.hwaAnnex = function(st, p, t, startup, d)
{
   // annexLand + moraleEarned/moraleLost
   var S = hwa.S;
   if(S.typ[t] != 1)
   {
      return undefined;
   }
   var o = st.ow[t];
   var human = S.human;
   var cap = S.cap[t];
   var est = S.est[t];
   var q;
   var cf;
   if(o >= 0 && o != p)
   {
      if(cap >= 0 && cap != o)
      {
         hwaMoraleAll(st,o,-30);
      }
      else if(cap < 0 && est == 1)
      {
         hwaMoraleAll(st,o,-10);
      }
      else if(est == 2)
      {
         hwaMoraleAll(st,o,-5);
      }
      if(cap == o)
      {
         q = 0;
         while(q < S.P)
         {
            cf = S.capF[q];
            if(q != o && st.ow[cf] == o && hwaArmyCount(st,q) == 0)
            {
               st.ap[cf] = q;
               st.ac[cf] = 99;
               st.am[cf] = 99;
               st.mv[cf] = 0;
               hwaAnnex(st,q,cf,true,null);
               if(d)
               {
                  d.notes.push("<font color=\'#FF9966\'>frees " + S.names[q] + " (99 troops)</font>");
               }
            }
            q++;
         }
      }
   }
   var all = 0;
   if(!startup && o != p)
   {
      var arm = 0;
      if(cap >= 0)
      {
         if(p == human && hwaProvinces(st,p) >= 2)
         {
            st.win = true;
            if(d)
            {
               d.notes.push("<font color=\'#66FF66\'><b>WINS THE GAME</b></font>");
            }
         }
         if(cap == o)
         {
            all = 50;
            arm = 30;
            if(d)
            {
               d.notes.push("<font color=\'#FFD700\'><b>DESTROYS " + S.names[o].toUpperCase() + "</b></font>");
            }
         }
         else
         {
            all = 30;
            arm = 20;
         }
      }
      else if(est == 1)
      {
         all = 10;
         arm = 10;
      }
      else if(est == 2)
      {
         all = 5;
         arm = 5;
      }
      else
      {
         all = 1;
      }
      hwaAddMorale(st,t,arm);
      if(d && est > 0)
      {
         d.notes.push("+" + (est != 1 ? "port " : "town ") + S.fld[t].town_name);
         if(d.kind == "move")
         {
            d.kind = "capture";
         }
      }
   }
   st.ow[t] = p;
   var peace = st.peace;
   var nbt = S.nb[t];
   var lands = 0;
   var k = 0;
   var nn;
   while(k < 6)
   {
      nn = nbt[k];
      if(nn >= 0 && S.typ[nn] == 1 && S.est[nn] == 0 && st.ap[nn] < 0 && !(peace >= 0 && st.ow[nn] == peace && p == human || p == peace && st.ow[nn] == human))
      {
         if(st.ow[nn] != p)
         {
            lands++;
         }
         st.ow[nn] = p;
      }
      k++;
   }
   if(!startup)
   {
      hwaMoraleAll(st,p,all + lands);
      if(d && lands)
      {
         d.notes.push("+" + lands + " land");
      }
   }
};
_global.hwaSpeechGain = function(st)
{
   var me = hwa.S.human;
   var g = 0;
   var i = 0;
   while(i < hwa.S.n)
   {
      if(st.ap[i] == me)
      {
         g += Math.min(50,st.ac[i] - st.am[i]);
      }
      i++;
   }
   return g;
};
_global.hwaApplySpecial = function(st, code, d)
{
   // -1 = give the speech (+50 morale to all your armies), -(10+q) = sign a pact with nation q.
   // Neither uses up a move.
   var S = hwa.S;
   st.moves.push(code);
   if(code == -1)
   {
      if(d)
      {
         d.kind = "speech";
         d.notes.push("+" + hwaSpeechGain(st) + " morale");
      }
      hwaMoraleAll(st,S.human,50);
      st.speech = 0;
   }
   else
   {
      st.peace = - code - 10;
      st.pact = 0;
      if(d)
      {
         d.kind = "pact";
         d.notes.push("they stop attacking you");
      }
   }
   return d;
};
_global.hwaApply = function(st, s, t, d)
{
   // moveArmy + attack + joinUnits
   var S = hwa.S;
   var human = S.human;
   var p = st.ap[s];
   var c = st.ac[s];
   var m = st.am[s];
   var c0 = c;
   if(st.peace >= 0 && (st.ow[t] == st.peace && p == human || p == st.peace && st.ow[t] == human))
   {
      hwaMoraleAll(st,st.ow[t],30);
      if(d)
      {
         d.notes.push("<font color=\'#FF6666\'>breaks pact with " + S.names[st.peace] + "</font>");
      }
      st.peace = -1;
   }
   st.ap[s] = -1;
   st.ac[s] = 0;
   st.am[s] = 0;
   st.mv[s] = 0;
   st.left--;
   st.moves.push(s * 1000 + t);
   var q = st.ap[t];
   var dc;
   var apw;
   var dpw;
   if(q >= 0 && q != p)
   {
      dc = st.ac[t];
      apw = c + m;
      dpw = dc + st.am[t];
      if(apw > dpw)
      {
         hwaMoraleAll(st,q,- Math.floor(dc / 10));
         c -= Math.floor(dpw / apw * c);
         if(c <= 0)
         {
            c = 1;
         }
         if(m > c)
         {
            m = c;
         }
         if(d)
         {
            d.kind = "attack";
            d.notes.push("beats " + S.names[q] + " " + dc + ", keeps " + c + "/" + c0);
         }
         st.ap[t] = p;
         st.ac[t] = c;
         st.am[t] = m;
         st.mv[t] = 1;
      }
      else
      {
         hwaMoraleAll(st,p,- Math.floor(c / 10));
         dc -= Math.floor(apw / dpw * c);
         if(dc <= 0)
         {
            dc = 1;
         }
         st.ac[t] = dc;
         if(st.am[t] > dc)
         {
            st.am[t] = dc;
         }
         if(d)
         {
            d.kind = "sacrifice";
            d.notes.push("<font color=\'#FF9966\'>army lost (" + apw + " vs " + dpw + "), enemy cut to " + dc + "</font>");
         }
         hwaUpdate(st);
         return d;
      }
   }
   else if(q == p)
   {
      var tc = st.ac[t];
      var tm = st.am[t];
      var add;
      if(tc + c <= 99)
      {
         st.ac[t] = tc + c;
         st.am[t] = Math.floor((tc * tm + c * m) / (tc + c));
      }
      else
      {
         add = 99 - tc;
         st.ac[t] = 99;
         st.am[t] = Math.floor((tc * tm + add * m) / 99);
         st.ap[s] = p;
         st.ac[s] = c - add;
         st.am[s] = m >= c - add ? c - add : m;
         st.mv[s] = 0;
      }
      if(st.am[t] > st.ac[t])
      {
         st.am[t] = st.ac[t];
      }
      st.mv[t] = 1;
      if(d)
      {
         d.kind = "merge";
         d.notes.push("joins army (now " + st.ac[t] + ")");
      }
   }
   else
   {
      st.ap[t] = p;
      st.ac[t] = c;
      st.am[t] = m;
      st.mv[t] = 1;
   }
   // an overflow army left behind by a merge is created after the game's army list, so it gets no morale from this move
   var keep = st.ap[s] != p ? -1 : st.am[s];
   hwaAnnex(st,p,t,false,d);
   if(keep >= 0)
   {
      st.am[s] = keep;
   }
   hwaUpdate(st);
   return d;
};
_global.hwaJoin = function(st, i, p, cnt, pm)
{
   var c;
   if(st.ap[i] < 0)
   {
      c = cnt <= 99 ? cnt : 99;
      st.ap[i] = p;
      st.ac[i] = c;
      st.am[i] = pm <= c ? pm : c;
      st.mv[i] = 0;
   }
   else if(st.ap[i] == p)
   {
      c = st.ac[i] + cnt;
      st.ac[i] = c <= 99 ? c : 99;
      if(st.am[i] > st.ac[i])
      {
         st.am[i] = st.ac[i];
      }
   }
};
_global.hwaEndTurn = function(st, me)
{
   // cleanupTurn (idle armies lose 1 morale) + unitsSpawn
   var S = hwa.S;
   var n = S.n;
   var i = 0;
   while(i < n)
   {
      if(st.ap[i] == me)
      {
         if(st.mv[i])
         {
            st.mv[i] = 0;
         }
         else
         {
            st.am[i] -= 1;
         }
      }
      i++;
   }
   hwaUpdate(st);
   var T = 0;
   var Pn = 0;
   var L = 0;
   var msum = 0;
   var acount = 0;
   i = 0;
   while(i < n)
   {
      if(st.ow[i] == me)
      {
         if(S.est[i] == 1)
         {
            T++;
         }
         else if(S.est[i] == 2)
         {
            Pn++;
         }
         else
         {
            L++;
         }
      }
      if(st.ap[i] == me)
      {
         msum += st.am[i];
         acount++;
      }
      i++;
   }
   if(T == 0)
   {
      return undefined;
   }
   var pm = !acount ? 10 : Math.floor(msum / acount);
   var uc = Math.floor((L + Pn * 5) / T);
   var q = 0;
   while(q < S.P)
   {
      if(st.ow[S.capF[q]] == me)
      {
         hwaJoin(st,S.capF[q],me,5,pm);
      }
      q++;
   }
   i = 0;
   while(i < n)
   {
      if(st.ow[i] == me && S.est[i] == 1)
      {
         hwaJoin(st,i,me,5 + uc,pm);
      }
      i++;
   }
   hwaUpdate(st);
};
_global.hwaTargetVal = function(st, j, me)
{
   var S = hwa.S;
   if(S.cap[j] >= 0)
   {
      return S.cap[j] != st.ow[j] ? 60 : 400;
   }
   if(S.est[j] == 1)
   {
      return 30;
   }
   if(S.est[j] == 2)
   {
      return 22;
   }
   return st.ow[j] == me ? 0 : 1;
};
_global.hwaFieldLoss = function(j, me, myA)
{
   var S = hwa.S;
   if(S.cap[j] == me)
   {
      return 30000;
   }
   if(S.cap[j] >= 0)
   {
      return 40 + 18 * myA;
   }
   if(S.est[j] == 1)
   {
      return 36 + 6 * myA;
   }
   if(S.est[j] == 2)
   {
      return 30 + 3 * myA;
   }
   return 0;
};
_global.hwaByLoss = function(a, b)
{
   return b.loss - a.loss;
};
_global.hwaThreatLoss = function(st, me, myA, detail, thrW)
{
   // each enemy nation gets up to 5 moves; greedily give it its most damaging attacks on you
   var S = hwa.S;
   var n = S.n;
   var ap = st.ap;
   var ac = st.ac;
   var am = st.am;
   var ow = st.ow;
   var cands = new Array();
   var gang = new Object();
   var gangT = new Array();
   var i = 0;
   var q;
   var epw;
   var r;
   var k;
   var j;
   var loss;
   var dpw;
   while(i < n)
   {
      q = ap[i];
      if(q >= 0 && q != me && q != st.peace)
      {
         epw = ac[i] + am[i];
         r = hwaReach(st,i);
         k = 0;
         while(k < r.length)
         {
            j = r[k];
            loss = 0;
            if(ap[j] == me)
            {
               dpw = ac[j] + am[j];
               if(epw > dpw)
               {
                  loss = ac[j] + 0.6 * am[j] + hwaFieldLoss(j,me,myA) - 0.35 * Math.floor(dpw / epw * ac[i]);
               }
               else if(HWA_W.gang > 0 || HWA_W.capGang > 0 && S.cap[j] == me)
               {
                  if(!gang[j])
                  {
                     gang[j] = new Array();
                     gangT.push(j);
                  }
                  gang[j].push(i);
               }
            }
            else if(ap[j] < 0 && ow[j] == me && S.est[j] > 0)
            {
               loss = hwaFieldLoss(j,me,myA);
            }
            if(loss > 0)
            {
               cands.push({e:i,t:j,q:q,loss:loss});
            }
            k++;
         }
      }
      i++;
   }
   cands.sort(hwaByLoss);
   var usedE = new Object();
   var usedT = new Object();
   var used = new Array(0,0,0,0,0,0,0,0);
   var total = 0;
   var c;
   i = 0;
   while(i < cands.length)
   {
      c = cands[i];
      if(!usedE[c.e] && !usedT[c.t] && used[c.q] < 5)
      {
         usedE[c.e] = true;
         usedT[c.t] = true;
         used[c.q]++;
         total += c.loss < 20000 ? c.loss * thrW : c.loss;
         if(detail)
         {
            detail.danger.push(c.t);
            if(c.loss >= 20000)
            {
               detail.capital = true;
            }
         }
      }
      i++;
   }
   // armies too strong for any single attacker but beatable by several in a row (what the AI's "wait for support" does)
   var g = 0;
   var list;
   var dc;
   var dm;
   var a;
   var apw;
   while(g < gangT.length)
   {
      j = gangT[g];
      if(!usedT[j])
      {
         list = gang[j];
         dc = ac[j];
         dm = am[j];
         k = 0;
         while(k < list.length)
         {
            a = list[k];
            if(!usedE[a])
            {
               apw = ac[a] + am[a];
               usedE[a] = true;
               if(apw > dc + dm)
               {
                  loss = ac[j] + 0.6 * am[j] + hwaFieldLoss(j,me,myA);
                  total += loss < 20000 ? loss * HWA_W.gang : loss * (HWA_W.capGang <= 0 ? 0.8 : HWA_W.capGang);
                  usedT[j] = true;
                  if(detail)
                  {
                     detail.danger.push(j);
                     if(loss >= 20000)
                     {
                        detail.capital = true;
                     }
                  }
                  break;
               }
               dc -= Math.floor(apw / (dc + dm) * ac[a]);
               if(dc <= 0)
               {
                  dc = 1;
               }
               if(dm > dc)
               {
                  dm = dc;
               }
            }
            k++;
         }
      }
      g++;
   }
   return total;
};
_global.hwaOpportunity = function(st, me)
{
   // what your armies could take on your next turn from where they stand
   var S = hwa.S;
   var n = S.n;
   var ap = st.ap;
   var ac = st.ac;
   var am = st.am;
   var ow = st.ow;
   var used = new Object();
   var total = 0;
   var i = 0;
   var pw;
   var r;
   var best;
   var bj;
   var k;
   var j;
   var v;
   while(i < n)
   {
      if(ap[i] == me)
      {
         pw = ac[i] + am[i];
         r = hwaReach(st,i);
         best = 0;
         bj = -1;
         k = 0;
         while(k < r.length)
         {
            j = r[k];
            v = 0;
            if(ap[j] >= 0 && ap[j] != me)
            {
               if(ap[j] != st.peace && pw > ac[j] + am[j])
               {
                  v = 0.6 * ac[j] + hwaTargetVal(st,j,me);
               }
            }
            else if(ap[j] < 0 && S.typ[j] == 1 && ow[j] != me && (ow[j] < 0 || ow[j] != st.peace))
            {
               v = hwaTargetVal(st,j,me);
            }
            if(v > best && !used[j])
            {
               best = v;
               bj = j;
            }
            k++;
         }
         if(bj >= 0)
         {
            used[bj] = true;
            total += best;
         }
      }
      i++;
   }
   return total;
};
_global.hwaEval = function(st0, detail)
{
   // value of ending the turn in this state
   var st = hwaClone(st0);
   hwaEndTurn(st,hwa.S.human);
   return hwaEvalCore(st,detail,!hwa.aggr ? HWA_W.threat : HWA_W.aggThreat,HWA_W.opp);
};
_global.hwaEvalCore = function(st, detail, thrW, oppW)
{
   var S = hwa.S;
   var me = S.human;
   var n = S.n;
   var ap = st.ap;
   var ac = st.ac;
   var am = st.am;
   var ow = st.ow;
   var dG = hwa.dGoal;
   var dC = hwa.dCap;
   var myC = 0;
   var myM = 0;
   var myA = 0;
   var enC = 0;
   var enM = 0;
   var inc = 0;
   var enInc = 0;
   var strat = 0;
   var tC = 0;
   var oC = 0;
   var W0 = HWA_W;
   var pot = 0;
   // aggressive mode: a target nation that is still alive
   var tgt = !hwa.aggr || hwa.target < 0 || ow[S.capF[hwa.target]] != hwa.target ? -1 : hwa.target;
   var i = 0;
   var a;
   var w;
   var o;
   while(i < n)
   {
      a = ap[i];
      if(a == me)
      {
         myC += ac[i];
         myM += am[i];
         myA++;
         pot += ac[i] < 50 ? ac[i] : 50;
         w = ac[i] / 30;
         if(w > 1)
         {
            w = 1;
         }
         strat -= (dG[i] * HWA_W.stratG + dC[i] * HWA_W.stratC) * w;
         if(tgt >= 0)
         {
            var dt = hwa.dTgt[i];
            if(hwa.dTgt2 && hwa.dTgt2[i] + HWA_W.t2Bias < dt)
            {
               dt = hwa.dTgt2[i] + HWA_W.t2Bias;
            }
            strat -= dt * HWA_W.stratT * w;
         }
      }
      else if(a >= 0)
      {
         enC += ac[i];
         enM += am[i];
         if(a == tgt)
         {
            tC += ac[i] + 0.6 * am[i];
            oC += ac[i] + W0.enemyMor * am[i];
         }
      }
      o = ow[i];
      if(o >= 0 && S.typ[i] == 1)
      {
         if(o == me)
         {
            inc += S.est[i] <= 0 ? 1 : 5;
         }
         else
         {
            enInc += S.est[i] <= 0 ? 1 : 5;
         }
      }
      i++;
   }
   var q = 0;
   var elim = 0;
   while(q < S.P)
   {
      o = ow[S.capF[q]];
      if(o == me)
      {
         inc += 5;
      }
      else
      {
         enInc += 5;
      }
      if(q != me && o != q)
      {
         elim++;
      }
      q++;
   }
   var W = HWA_W;
   var hold = (!st.speech ? 0 : (!hwa.aggr ? W.speechHold : W.aggSpeechHold) * hwa.speechPot) + (!st.pact || st.peace >= 0 ? 0 : W.pactHold);
   var score = hold + myC + W.myMor * myM - W.enemy * (enC + W.enemyMor * enM) + W.inc * inc - W.enInc * enInc + (!hwa.aggr ? W.elim : W.aggElim) * elim + strat;
   if(tgt >= 0 && W.aggOther != 1)
   {
      // troops of nations other than the target count for less (or more) than usual
      score += W.enemy * (1 - W.aggOther) * (enC + W.enemyMor * enM - oC);
   }
   if(tgt >= 0)
   {
      score -= (W.tgtEnemy - W.enemy) * tC;
      var sg = hwaSiege(st,me,tgt,null);
      score += W.siege * sg;
      if(detail)
      {
         detail.siege = sg;
      }
   }
   if(st.win)
   {
      score += 1000000;
   }
   if(ow[S.capF[me]] != me)
   {
      score -= 1000000;
   }
   var threat = thrW <= 0 ? 0 : hwaThreatLoss(st,me,myA,detail,thrW);
   score += oppW * hwaOpportunity(st,me) - threat;
   if(detail)
   {
      detail.inc = inc;
      detail.power = myC + myM;
      detail.threat = threat;
   }
   return score;
};
_global.hwaBFS = function(src)
{
   // path distance (in hexes) from every field to the nearest field in src, respecting land/sea/port rules
   var S = hwa.S;
   var n = S.n;
   var d = new Array(n);
   var i = 0;
   while(i < n)
   {
      d[i] = 40;
      i++;
   }
   var queue = new Array();
   i = 0;
   while(i < src.length)
   {
      d[src[i]] = 0;
      queue.push(src[i]);
      i++;
   }
   var h = 0;
   var v;
   var nv;
   var k;
   var u;
   while(h < queue.length)
   {
      v = queue[h];
      h++;
      nv = S.nb[v];
      k = 0;
      while(k < 6)
      {
         u = nv[k];
         if(u >= 0 && d[u] > d[v] + 1 && (S.typ[u] == 0 || S.typ[v] == 1 || S.est[u] == 2))
         {
            d[u] = d[v] + 1;
            queue.push(u);
         }
         k++;
      }
   }
   return d;
};
_global.hwaByPw = function(a, b)
{
   return b.pw - a.pw;
};
_global.hwaSiege = function(st, me, q, info)
{
   // can your armies take q's capital on your next move?  1 = yes (possibly by chipping it down
   // with several attacks in a row and finishing with the strongest), less = partial progress
   var S = hwa.S;
   var cf = S.capF[q];
   var dc = 0;
   var dm = 0;
   if(st.ap[cf] >= 0 && st.ap[cf] != me)
   {
      dc = st.ac[cf];
      dm = st.am[cf];
   }
   var att = new Array();
   var i = 0;
   var r;
   var k;
   while(i < S.n)
   {
      if(st.ap[i] == me)
      {
         r = hwaReach(st,i);
         k = 0;
         while(k < r.length)
         {
            if(r[k] == cf)
            {
               att.push({i:i,c:st.ac[i],m:st.am[i],pw:st.ac[i] + st.am[i]});
               break;
            }
            k++;
         }
      }
      i++;
   }
   if(info)
   {
      info.def = dc + dm;
      info.att = att.length;
      info.reach = 0;
   }
   if(!att.length)
   {
      return 0;
   }
   att.sort(hwaByPw);
   var total = 0;
   i = 0;
   while(i < att.length && i < 5)
   {
      total += att[i].pw;
      i++;
   }
   if(info)
   {
      info.reach = total;
   }
   if(dc + dm == 0)
   {
      return 1;
   }
   var fin = att[0];
   var fm = fin.m;
   var lost = 0;
   var dpw;
   k = 1;
   while(fin.c + fm <= dc + dm && k < att.length && k < 5)
   {
      // a failed attack wears the defender down, but costs you the army and morale everywhere
      dpw = dc + dm;
      dc -= Math.floor(att[k].pw / dpw * att[k].c);
      if(dc <= 0)
      {
         dc = 1;
      }
      if(dm > dc)
      {
         dm = dc;
      }
      fm -= Math.floor(att[k].c / 10);
      if(fm < 0)
      {
         fm = 0;
      }
      lost += att[k].c;
      k++;
   }
   if(fin.c + fm > dc + dm)
   {
      if(info)
      {
         info.chips = k - 1;
      }
      return 1 - Math.min(0.5,lost / 400);
   }
   return HWA_W.sigPart * Math.min(1,total / (2 * (info ? info.def : st.ac[cf] + st.am[cf]) + 1));
};
_global.hwaPickTarget = function(st, me)
{
   // the enemy nation that is cheapest to wipe out: weak capital garrison, low total power, close to your armies
   var S = hwa.S;
   var tp = hwaPowers(st);
   var best = -1;
   var bc = 0;
   var prevCost = -1;
   var q = 0;
   var cf;
   var def;
   var d;
   var near;
   var i;
   var cost;
   while(q < S.P)
   {
      if(q != me && q != st.peace && st.ow[S.capF[q]] == q && hwaArmyCount(st,q) > 0)
      {
         cf = S.capF[q];
         def = st.ap[cf] != q ? 0 : st.ac[cf] + st.am[cf];
         d = hwaBFS([cf]);
         near = 40;
         i = 0;
         while(i < S.n)
         {
            if(st.ap[i] == me && st.ac[i] >= 15 && d[i] < near)
            {
               near = d[i];
            }
            i++;
         }
         cost = def * HWA_W.tgtDef + tp[q] * HWA_W.tgtPow + near * HWA_W.tgtDist;
         if(q == hwa.target)
         {
            prevCost = cost;
         }
         if(best < 0 || cost < bc)
         {
            best = q;
            bc = cost;
         }
      }
      q++;
   }
   // stick with the current target unless another one is clearly easier
   if(prevCost >= 0 && prevCost <= bc / HWA_W.tgtStick)
   {
      best = hwa.target;
   }
   hwa.target = best;
   hwa.dTgt = best < 0 ? null : hwaBFS([S.capF[best]]);
   // the next-easiest nation: distant armies can start moving toward it before the current target falls
   hwa.dTgt2 = null;
   if(HWA_W.t2 && best >= 0)
   {
      var b2 = -1;
      var c2 = 0;
      q = 0;
      while(q < S.P)
      {
         if(q != me && q != best && q != st.peace && st.ow[S.capF[q]] == q && hwaArmyCount(st,q) > 0)
         {
            cf = S.capF[q];
            def = st.ap[cf] != q ? 0 : st.ac[cf] + st.am[cf];
            cost = def * HWA_W.tgtDef + tp[q] * HWA_W.tgtPow;
            if(b2 < 0 || cost < c2)
            {
               b2 = q;
               c2 = cost;
            }
         }
         q++;
      }
      if(b2 >= 0)
      {
         hwa.target2 = b2;
         hwa.dTgt2 = hwaBFS([S.capF[b2]]);
      }
   }
};
_global.hwaPrepare = function(st, me)
{
   // per-turn map analysis: distances to targets + the current enemy threat map
   var S = hwa.S;
   var n = S.n;
   var goal = new Array();
   var capg = new Array();
   var i = 0;
   while(i < n)
   {
      if(S.typ[i] == 1 && S.est[i] > 0 && st.ow[i] != me && !(st.peace >= 0 && st.ow[i] == st.peace))
      {
         goal.push(i);
      }
      i++;
   }
   var q = 0;
   while(q < S.P)
   {
      if(q != me && q != st.peace && st.ow[S.capF[q]] == q)
      {
         capg.push(S.capF[q]);
      }
      q++;
   }
   hwa.dGoal = hwaBFS(goal);
   hwa.dCap = hwaBFS(capg);
   // what the speech could ever add with today's army (used to value keeping it for later)
   hwa.speechPot = 0;
   i = 0;
   while(i < n)
   {
      if(st.ap[i] == me)
      {
         hwa.speechPot += st.ac[i] < 50 ? st.ac[i] : 50;
      }
      i++;
   }
   if(hwa.aggr)
   {
      hwaPickTarget(st,me);
   }
   else
   {
      hwa.target = -1;
   }
   hwa.rootThreat = new Array(n);
   hwa.rootDanger = new Array(n);
   i = 0;
   while(i < n)
   {
      hwa.rootThreat[i] = 0;
      hwa.rootDanger[i] = 0;
      i++;
   }
   var myA = hwaArmyCount(st,me);
   var r;
   var k;
   var pw;
   i = 0;
   while(i < n)
   {
      if(st.ap[i] >= 0 && st.ap[i] != me && st.ap[i] != st.peace)
      {
         pw = st.ac[i] + st.am[i];
         r = hwaReach(st,i);
         k = 0;
         while(k < r.length)
         {
            if(hwa.rootThreat[r[k]] < pw)
            {
               hwa.rootThreat[r[k]] = pw;
            }
            k++;
         }
      }
      i++;
   }
   i = 0;
   while(i < n)
   {
      if(st.ow[i] == me && hwa.rootThreat[i] > (st.ap[i] != me ? 0 : st.ac[i] + st.am[i]))
      {
         hwa.rootDanger[i] = hwaFieldLoss(i,me,myA);
      }
      i++;
   }
};
_global.hwaQuick = function(st, s, t)
{
   // cheap estimate used only to choose which moves get the full simulation
   var S = hwa.S;
   var me = S.human;
   var c = st.ac[s];
   var m = st.am[s];
   var v = 0;
   var q = st.ap[t];
   var dpw;
   var lost;
   if(q >= 0 && q != me)
   {
      dpw = st.ac[t] + st.am[t];
      if(c + m <= dpw)
      {
         if(hwa.aggr && hwa.target >= 0 && t == S.capF[hwa.target])
         {
            return - c * 0.3 + 20;
         }
         return - c + 0.35 * Math.floor((c + m) / dpw * c) - 5 + (S.cap[t] < 0 ? 0 : 15);
      }
      lost = Math.floor(dpw / (c + m) * c);
      v += 0.35 * (st.ac[t] + 0.6 * st.am[t]) - lost;
      c -= lost;
   }
   else if(q == me)
   {
      c += st.ac[t];
      m = st.am[t];
   }
   if(S.typ[t] == 1 && st.ow[t] != me)
   {
      v += hwaTargetVal(st,t,me) * 1.5;
   }
   if(S.typ[t] == 1)
   {
      var k = 0;
      var nn;
      while(k < 6)
      {
         nn = S.nb[t][k];
         if(nn >= 0 && S.typ[nn] == 1 && S.est[nn] == 0 && st.ap[nn] < 0 && st.ow[nn] != me)
         {
            v += 7;
         }
         k++;
      }
   }
   v += (hwa.dGoal[s] - hwa.dGoal[t]) * 0.6;
   if(hwa.aggr && hwa.target >= 0)
   {
      v += (hwa.dTgt[s] - hwa.dTgt[t]) * HWA_W.qT * Math.min(1,c / 30);
      if(q == hwa.target)
      {
         v += 10;
      }
   }
   if(hwa.rootThreat[t] > c + m)
   {
      v -= c * 0.8;
   }
   v += hwa.rootDanger[t] * 0.5;
   if(hwa.rootThreat[s] > st.ac[s] + st.am[s])
   {
      v += st.ac[s] * 0.4;
   }
   else if(hwa.rootThreat[s] > 0 && S.est[s] > 0)
   {
      v -= hwaFieldLoss(s,me,4) * 0.5;
   }
   return v;
};
_global.hwaByQ = function(a, b)
{
   return b.q - a.q;
};
_global.hwaByScore = function(a, b)
{
   return b.score - a.score;
};
_global.hwaKey = function(st)
{
   var h = 0;
   var i = 0;
   var n = hwa.S.n;
   while(i < n)
   {
      if(st.ap[i] >= 0)
      {
         h = (h * 31 + i * 1009 + st.ap[i] * 101 + st.ac[i] * 7 + st.am[i]) % 1000000007;
      }
      i++;
   }
   return h + "|" + st.left + "|" + st.speech + st.pact + "|" + st.peace;
};
_global.hwaDist = function(a, b)
{
   // getDistance
   var S = hwa.S;
   var ax = S.fx[a] * 5;
   var bx = S.fx[b] * 5;
   var ay = S.fx[a] % 2 != 0 ? S.fy[a] * 10 + 5 : S.fy[a] * 10;
   var by = S.fx[b] % 2 != 0 ? S.fy[b] * 10 + 5 : S.fy[b] * 10;
   return Math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
};
_global.hwaPowers = function(st)
{
   var S = hwa.S;
   var tp = new Array(0,0,0,0,0,0,0,0);
   var i = 0;
   while(i < S.n)
   {
      if(st.ap[i] >= 0)
      {
         tp[st.ap[i]] += st.ac[i] + st.am[i];
      }
      i++;
   }
   return tp;
};
_global.hwaAIProf = function(st, party, f, a, X)
{
   // the game's finalProfitability(), on the model
   var S = hwa.S;
   var v = -10000000;
   var pr = S.prof[f];
   var q = 0;
   var t;
   while(q < S.P)
   {
      if(q != party)
      {
         t = 0;
         if(st.ow[S.capF[q]] == q)
         {
            t = pr[q];
            if(q == X.human)
            {
               t += X.diff * 2;
            }
         }
         if(X.peace == party && q == X.human && !X.duel)
         {
            t -= 500;
         }
         if(v < t)
         {
            v = t;
         }
      }
      q++;
   }
   if(X.peace == party && X.human == st.ow[f] && !X.duel)
   {
      v -= 500;
   }
   var capt = false;
   var fa = st.ap[f];
   var apw = st.ac[a] + st.am[a];
   var fpw = fa < 0 ? NaN : st.ac[f] + st.am[f];
   if(S.typ[f] == 1 && st.ow[f] != party)
   {
      if(S.cap[f] >= 0 && S.cap[f] == st.ow[f] && apw > fpw)
      {
         v += 1000000;
         capt = true;
      }
      else if(S.cap[f] >= 0)
      {
         v += 20;
      }
      else if(S.est[f] == 1)
      {
         v += 5;
      }
      else if(S.est[f] == 2)
      {
         v += 3;
      }
      else if(S.ntown[f])
      {
         v += 3;
      }
   }
   if(fa >= 0 && fa != party)
   {
      var fp = st.ow[f];
      if(fa != X.human && fp >= 0 && X.tp[fp] > 1.5 * X.tp[party] && fpw > apw && (fp < 2 && party < 2 || fp > 1 && party > 1))
      {
         v += 200;
      }
      if(X.diff > 5 && fa != X.human)
      {
         v -= 250;
      }
   }
   if(fa == party && st.ac[f] > st.ac[a] && st.ac[f] < 70)
   {
      v += 2;
   }
   if(S.cap[a] == party && fa < 0 && X.turns < 5)
   {
      v += 50;
   }
   var ring = S.ring[f];
   var own = 0;
   var en = 0;
   var k = 0;
   var r;
   while(k < ring.length)
   {
      r = ring[k];
      if(st.ap[r] >= 0)
      {
         if(st.ap[r] == party)
         {
            own += st.ac[r] + st.am[r];
         }
         else
         {
            en += st.ac[r] + st.am[r];
         }
      }
      k++;
   }
   if((own < en && own < 300 || apw < fpw && st.ac[a] < 90) && !capt)
   {
      if(X.wfsField == f)
      {
         if(X.wfsCount < 5)
         {
            X.wfs[f] = true;
         }
         else
         {
            v -= 5;
         }
      }
      else
      {
         X.wfs[f] = true;
      }
   }
   return v;
};
// The game's AI picks moves by sorting lists with Flash's built-in Array.sort, which is an unstable
// quicksort (pivot = first element). To pick the same move on ties, these lists are built exactly like
// the game builds them (same order, including the duplicate entries getPossibleMoves produces) and
// sorted with the same comparison rules; inside Flash, Array.sort is the same sort.
_global.hwaAIOrderMoves = function(a, b)
{
   if(a.p > b.p)
   {
      return -1;
   }
   if(a.p < b.p)
   {
      return 1;
   }
   return 0;
};
_global.hwaAIOrder = function(a, b)
{
   // orderArmies: profitability, then power
   if(a.p > b.p)
   {
      return -1;
   }
   if(a.p < b.p)
   {
      return 1;
   }
   if(a.pw > b.pw)
   {
      return -1;
   }
   if(a.pw < b.pw)
   {
      return 1;
   }
   return 0;
};
_global.hwaReachDup = function(st, s)
{
   // getPossibleMoves(field, true, false) exactly, duplicates and order included
   var S = hwa.S;
   var nb = S.nb;
   var typ = S.typ;
   var est = S.est;
   var ap = st.ap;
   var ac = st.ac;
   var p = ap[s];
   var out = new Array();
   var ns = nb[s];
   var k = 0;
   var n1;
   var nn;
   var kk;
   var ns2;
   var isPort = est[s] == 2;
   var isSea = typ[s] == 0;
   while(k < 6)
   {
      n1 = ns[k];
      if(n1 >= 0 && (isPort || isSea || typ[n1] == 1) && (ap[n1] < 0 || ap[n1] != p || typ[n1] == 1 && ac[n1] < 99))
      {
         out.push(n1);
         ns2 = nb[n1];
         if(isPort)
         {
            if(typ[n1] == 0 && ap[n1] < 0)
            {
               kk = 0;
               while(kk < 6)
               {
                  nn = ns2[kk];
                  if(nn >= 0 && nn != s && typ[nn] == 0 && (ap[nn] < 0 || ap[nn] != p))
                  {
                     out.push(nn);
                  }
                  kk++;
               }
            }
            else if(typ[n1] == 1 && est[n1] == 0 && ap[n1] < 0)
            {
               kk = 0;
               while(kk < 6)
               {
                  nn = ns2[kk];
                  if(nn >= 0 && nn != s && typ[nn] == 1 && (ap[nn] < 0 || ap[nn] != p || ac[nn] < 99))
                  {
                     out.push(nn);
                  }
                  kk++;
               }
            }
         }
         else if(isSea)
         {
            if(typ[n1] == 0 && ap[n1] < 0)
            {
               kk = 0;
               while(kk < 6)
               {
                  nn = ns2[kk];
                  if(nn >= 0 && nn != s && (ap[nn] < 0 || ap[nn] != p || typ[nn] == 1 && ac[nn] < 99))
                  {
                     out.push(nn);
                  }
                  kk++;
               }
            }
         }
         else if(est[n1] == 0 && ap[n1] < 0)
         {
            kk = 0;
            while(kk < 6)
            {
               nn = ns2[kk];
               if(nn >= 0 && nn != s && typ[nn] == 1 && (ap[nn] < 0 || ap[nn] != p || ac[nn] < 99))
               {
                  out.push(nn);
               }
               kk++;
            }
         }
      }
      k++;
   }
   return out;
};
_global.hwaAIApply = function(st, q, s, t, X)
{
   var me = hwa.S.human;
   if(t < 0)
   {
      // the game "moves" an army that has nowhere to go: it loses its hex and drops out of the game
      st.ap[s] = -1;
      st.ac[s] = 0;
      st.am[s] = 0;
      st.mv[s] = 0;
      hwaUpdate(st);
      return undefined;
   }
   if(!X.log || st.ow[t] != me && st.ap[t] != me)
   {
      hwaApply(st,s,t,null);
      return undefined;
   }
   var e = {q:q,s:s,t:t,apw:st.ac[s] + st.am[s],dpw:st.ap[t] != me ? 0 : st.ac[t] + st.am[t],army:st.ap[t] == me};
   hwaApply(st,s,t,null);
   e.took = st.ap[t] == q || st.ow[t] == q;
   X.log.push(e);
};
_global.hwaAIMove = function(st, party, X)
{
   // the game's makeMove()/calcArmiesProfitability()/supportArmy(), list for list
   var S = hwa.S;
   var n = S.n;
   var list = new Array();
   var i = 0;
   var r;
   var k;
   var mvl;
   var m;
   X.tp = hwaPowers(st);
   while(i < n)
   {
      if(st.ap[i] == party && !st.mv[i])
      {
         r = hwaReachDup(st,i);
         mvl = new Array();
         k = 0;
         while(k < r.length)
         {
            X.wfs[r[k]] = false;
            mvl.push({f:r[k],p:hwaAIProf(st,party,r[k],i,X)});
            k++;
         }
         mvl.sort(hwaAIOrderMoves);
         m = !mvl.length ? null : mvl[0];
         list.push({a:i,m:!m ? -1 : m.f,p:!m ? NaN : (S.cap[i] == party && X.turns > 5 ? m.p - 1000 : m.p),pw:st.ac[i] + st.am[i]});
      }
      i++;
   }
   if(!list.length)
   {
      return false;
   }
   list.sort(hwaAIOrder);
   var top = list[0];
   if(top.m < 0 || !X.wfs[top.m])
   {
      X.wfsField = -1;
      X.wfsCount = 0;
      hwaAIApply(st,party,top.a,top.m,X);
      return true;
   }
   if(top.m == X.wfsField)
   {
      X.wfsCount++;
   }
   else
   {
      X.wfsField = top.m;
      X.wfsCount = 0;
   }
   var f = top.m;
   var sup = new Array();
   var g;
   i = 0;
   while(i < n)
   {
      if(st.ap[i] == party && !st.mv[i] && i != top.a && S.cap[i] != party)
      {
         r = hwaReachDup(st,i);
         mvl = new Array();
         k = 0;
         while(k < r.length)
         {
            g = r[k];
            if(g != f && (st.ap[g] < 0 || st.ap[g] == party))
            {
               mvl.push({f:g,p:- hwaDist(g,f)});
            }
            k++;
         }
         mvl.sort(hwaAIOrderMoves);
         if(!mvl.length)
         {
            sup.push({a:i,m:-1,p:NaN,pw:st.ac[i] + st.am[i]});
         }
         else if(mvl[0].f != f)
         {
            sup.push({a:i,m:mvl[0].f,p:mvl[0].p,pw:st.ac[i] + st.am[i]});
         }
      }
      i++;
   }
   if(sup.length > 0)
   {
      sup.sort(hwaAIOrder);
      hwaAIApply(st,party,sup[0].a,sup[0].m,X);
   }
   else
   {
      hwaAIApply(st,party,top.a,top.m,X);
   }
   return true;
};
_global.hwaAIContext = function(B)
{
   var S = hwa.S;
   var X = {human:S.human,diff:_root.difficulty,turns:B.turns,wfs:new Array(S.n),wfsF:new Array(),wfsC:new Array()};
   var q = 0;
   while(q < S.P)
   {
      X.wfsF[q] = !B.hw_parties_wait_for_support_field[q] ? -1 : B.hw_parties_wait_for_support_field[q].hwa_i;
      X.wfsC[q] = !B.hw_parties_wait_for_support_count[q] ? 0 : B.hw_parties_wait_for_support_count[q];
      q++;
   }
   return X;
};
_global.hwaEnemyRound = function(st, X0)
{
   // play every enemy nation's next turn with the game's own AI
   var S = hwa.S;
   var me = S.human;
   var X = {human:X0.human,diff:X0.diff,turns:X0.turns,wfs:new Array(S.n),wfsF:X0.wfsF.slice(),wfsC:X0.wfsC.slice(),log:X0.log};
   var q = me + 1;
   var c = 0;
   var z;
   var di;
   var mp;
   var movable;
   var i;
   while(c < S.P - 1)
   {
      if(q >= S.P)
      {
         q = 0;
      }
      if(hwaArmyCount(st,q) > 0)
      {
         di = 0;
         z = 0;
         while(z < S.P)
         {
            if(st.ow[S.capF[z]] == z)
            {
               di++;
            }
            z++;
         }
         X.duel = di < 3;
         X.peace = st.peace;
         X.wfsField = X.wfsF[q];
         X.wfsCount = X.wfsC[q];
         mp = Math.min(5,hwaArmyCount(st,q));
         while(mp > 0)
         {
            movable = 0;
            i = 0;
            while(i < S.n)
            {
               if(st.ap[i] == q && !st.mv[i])
               {
                  movable++;
               }
               i++;
            }
            if(mp > movable)
            {
               mp = movable;
            }
            if(mp <= 0)
            {
               break;
            }
            hwaAIMove(st,q,X);
            mp--;
            if(st.ow[S.capF[me]] != me)
            {
               return undefined;
            }
         }
         X.wfsF[q] = X.wfsField;
         X.wfsC[q] = X.wfsCount;
         hwaEndTurn(st,q);
      }
      q++;
      c++;
   }
};
_global.hwaPoolAdd = function(J, st)
{
   // keep the best few complete plans for the enemy-reply check
   var R = HWA_W.rerank;
   if(J.pool.length < R)
   {
      J.pool.push(st);
      return undefined;
   }
   var w = 0;
   var i = 1;
   while(i < J.pool.length)
   {
      if(J.pool[i].score < J.pool[w].score)
      {
         w = i;
      }
      i++;
   }
   if(st.score > J.pool[w].score)
   {
      J.pool[w] = st;
   }
};
_global.hwaGreedyTurn = function(st, me)
{
   // a quick version of your next turn: repeatedly play the move the cheap estimate likes best
   var S = hwa.S;
   var left = Math.min(HWA_W.ply2Moves,hwaArmyCount(st,me));
   var best;
   var bs;
   var bt;
   var v;
   var i;
   var r;
   var k;
   while(left > 0)
   {
      best = -1;
      bs = 0;
      bt = -1;
      i = 0;
      while(i < S.n)
      {
         if(st.ap[i] == me && !st.mv[i])
         {
            r = hwaReach(st,i);
            k = 0;
            while(k < r.length)
            {
               v = hwaQuick(st,i,r[k]);
               if(v > bs)
               {
                  bs = v;
                  best = i;
                  bt = r[k];
               }
               k++;
            }
         }
         i++;
      }
      if(best < 0)
      {
         break;
      }
      hwaApply(st,best,bt,null);
      left--;
   }
};
_global.hwaRerank = function(J, st)
{
   var s2 = hwaClone(st);
   hwaEndTurn(s2,hwa.S.human);
   J.X.log = new Array();
   hwaEnemyRound(s2,J.X);
   if(HWA_W.ply2 && s2.ow[hwa.S.capF[hwa.S.human]] == hwa.S.human)
   {
      var log = J.X.log;
      J.X.log = null;
      hwaGreedyTurn(s2,hwa.S.human);
      J.X.log = log;
   }
   st.pred = J.X.log;
   J.X.log = null;
   st.det2 = {danger:new Array(),capital:false};
   st.score2 = hwaEvalCore(s2,st.det2,!hwa.aggr ? HWA_W.threat2 : HWA_W.aggThreat2,!hwa.aggr ? HWA_W.opp2 : HWA_W.aggOpp2) + HWA_W.mix * st.score;
   st.capLost = s2.ow[hwa.S.capF[hwa.S.human]] != hwa.S.human;
};
_global.hwaPickReranked = function(J)
{
   var b = -1;
   var i = 0;
   while(i < J.ri)
   {
      if(b < 0 || J.pool[i].score2 > J.pool[b].score2)
      {
         b = i;
      }
      i++;
   }
   if(b >= 0)
   {
      J.best = J.pool[b];
   }
};
_global.hwaStartSearch = function(B)
{
   hwaBuildStatic(B);
   var me = hwa.S.human;
   var root = hwaRootState(B);
   hwaPrepare(root,me);
   root.score = hwaEval(root,null);
   hwa.job = {beams:new Array(root),next:new Array(),bi:0,depth:0,best:root,root:root,done:false,seen:new Object(),t0:getTimer(),pool:new Array(root),stage:0,ri:0,X:hwaAIContext(B),cut:false};
   hwa.thinking = true;
   hwa.plan = new Array();
};
_global.hwaStep = function()
{
   // one unit of work: expand one state of the current beam
   var J = hwa.job;
   var S = hwa.S;
   var me = S.human;
   if(J.stage == 1)
   {
      // stage 2: replay the enemies' turn for each top plan
      if(J.ri < J.pool.length)
      {
         hwaRerank(J,J.pool[J.ri]);
         J.ri++;
         return undefined;
      }
      hwaPickReranked(J);
      J.done = true;
      return undefined;
   }
   if(J.bi >= J.beams.length)
   {
      J.next.sort(hwaByScore);
      J.beams = J.next.slice(0,HWA_W.beam);
      J.next = new Array();
      J.bi = 0;
      J.depth++;
      if(!J.beams.length)
      {
         J.stage = HWA_W.rerank <= 0 ? 2 : 1;
         J.done = J.stage == 2;
      }
      return undefined;
   }
   var st = J.beams[J.bi];
   J.bi++;
   if(st.left <= 0)
   {
      return undefined;
   }
   var cands = new Array();
   var i = 0;
   var n = S.n;
   var r;
   var k;
   while(i < n)
   {
      if(st.ap[i] == me && !st.mv[i])
      {
         r = hwaReach(st,i);
         k = 0;
         while(k < r.length)
         {
            cands.push({s:i,t:r[k],q:hwaQuick(st,i,r[k])});
            k++;
         }
      }
      i++;
   }
   cands.sort(hwaByQ);
   // the top candidates overall, plus each army's own best idea
   var pick = new Array();
   var armyDone = new Object();
   var c = 0;
   while(c < cands.length && pick.length < HWA_W.maxcand)
   {
      if(c < HWA_W.cand || !armyDone[cands[c].s])
      {
         pick.push(cands[c]);
         armyDone[cands[c].s] = true;
      }
      c++;
   }
   if(hwa.aggr && hwa.target >= 0)
   {
      var tcf = S.capF[hwa.target];
      var extra = 0;
      c = 0;
      while(c < cands.length && extra < 6)
      {
         if(cands[c].t == tcf || st.ap[cands[c].t] == hwa.target)
         {
            var dup = false;
            var z = 0;
            while(z < pick.length)
            {
               if(pick[z] == cands[c])
               {
                  dup = true;
               }
               z++;
            }
            if(!dup)
            {
               pick.push(cands[c]);
               extra++;
            }
         }
         c++;
      }
   }
   if(st.speech)
   {
      pick.push({s:-1,t:-1,code:-1});
   }
   if(st.pact && st.peace < 0)
   {
      var alive = 0;
      var q2 = 0;
      while(q2 < S.P)
      {
         if(st.ow[S.capF[q2]] == q2)
         {
            alive++;
         }
         q2++;
      }
      // pacts only bind the AI while at least three nations still hold their capitals
      q2 = 0;
      while(alive >= 3 && q2 < S.P)
      {
         if(q2 != me && st.ow[S.capF[q2]] == q2 && hwaArmyCount(st,q2) > 0)
         {
            pick.push({s:-1,t:-1,code:-10 - q2});
         }
         q2++;
      }
   }
   var ch;
   var key;
   c = 0;
   while(c < pick.length)
   {
      ch = hwaClone(st);
      if(pick[c].code < 0)
      {
         hwaApplySpecial(ch,pick[c].code,null);
      }
      else
      {
         hwaApply(ch,pick[c].s,pick[c].t,null);
      }
      ch.score = hwaEval(ch,null);
      key = hwaKey(ch);
      if(!J.seen[key])
      {
         J.seen[key] = true;
         J.next.push(ch);
         if(ch.score > J.best.score)
         {
            J.best = ch;
         }
         hwaPoolAdd(J,ch);
      }
      c++;
   }
};
_global.hwaFinish = function()
{
   var J = hwa.job;
   var best = J.best;
   var st = hwaClone(J.root);
   hwa.plan = new Array();
   var i = 0;
   var mv;
   var d;
   while(i < best.moves.length)
   {
      mv = best.moves[i];
      if(mv < 0)
      {
         d = {kind:"special",notes:new Array(),s:-1,t:-1,code:mv};
         hwaApplySpecial(st,mv,d);
      }
      else
      {
         d = {kind:"move",notes:new Array(),s:Math.floor(mv / 1000),t:mv % 1000,code:mv};
         d.count = st.ac[d.s];
         hwaApply(st,d.s,d.t,d);
      }
      hwa.plan.push(d);
      i++;
   }
   hwa.endEarly = best.left > 0 && !J.cut;
   hwa.det0 = {danger:new Array(),capital:false};
   hwa.det1 = {danger:new Array(),capital:false};
   hwa.rootScore = hwaEval(J.root,hwa.det0);
   hwa.planScore = hwaEval(best,hwa.det1);
   hwa.predict = !best.pred ? null : best.pred;
   hwa.capLost = !!best.capLost;
   hwa.danger = new Array();
   if(hwa.predict)
   {
      i = 0;
      while(i < hwa.predict.length)
      {
         if(hwa.predict[i].took)
         {
            hwa.danger.push(hwa.predict[i].t);
         }
         i++;
      }
   }
   else
   {
      hwa.danger = hwa.det1.danger;
   }
   hwa.depth = J.depth;
   hwa.thinkTime = getTimer() - J.t0;
   // confidence: how much the strongest alternative plans agree with each step (weighted by how close they score)
   var useS2 = J.ri > 0;
   var bs = !useS2 ? best.score : best.score2;
   var cn = !useS2 ? J.pool.length : J.ri;
   var wsum = 0;
   var wts = new Array();
   var k = 0;
   var sc;
   while(k < cn)
   {
      sc = !useS2 ? J.pool[k].score : J.pool[k].score2;
      wts[k] = Math.exp(Math.max(-30,(sc - bs) / HWA_W.confT));
      wsum += wts[k];
      k++;
   }
   i = 0;
   var agree;
   var z;
   while(i < hwa.plan.length)
   {
      mv = hwa.plan[i].code;
      agree = 0;
      k = 0;
      while(k < cn)
      {
         z = 0;
         while(z < J.pool[k].moves.length)
         {
            if(J.pool[k].moves[z] == mv)
            {
               agree += wts[k];
               break;
            }
            z++;
         }
         k++;
      }
      hwa.plan[i].conf = wsum <= 0 ? 100 : Math.round(100 * agree / wsum);
      i++;
   }
   // automatic speed: shrink the search if it was slow, grow it if there was time to spare
   if(HWA_W.autoSpeed)
   {
      if(J.cut || hwa.thinkTime > HWA_SLOW)
      {
         hwaSetLevel(hwa.level - 1);
      }
      else if(hwa.thinkTime < HWA_FAST)
      {
         hwaSetLevel(hwa.level + 1);
      }
   }
   hwa.tgtInfo = null;
   if(hwa.aggr && hwa.target >= 0)
   {
      hwa.tgtInfo = {def:0,att:0,reach:0,chips:0};
      hwa.tgtInfo.now = hwaSiege(J.root,hwa.S.human,hwa.target,hwa.tgtInfo);
      hwa.tgtInfo.dist = 40;
      var ti = 0;
      while(ti < hwa.S.n)
      {
         if(J.root.ap[ti] == hwa.S.human && hwa.dTgt[ti] < hwa.tgtInfo.dist)
         {
            hwa.tgtInfo.dist = hwa.dTgt[ti];
         }
         ti++;
      }
   }
   hwa.thinking = false;
   hwa.job = null;
};
_global.hwaSnapshotPrediction = function(B)
{
   // your turn just ended (units spawned): replay the enemies' round from the moves you made
   if(!hwa.S || hwa.S.board != B)
   {
      hwaBuildStatic(B);
   }
   var st = hwaRootState(B);
   hwa.predStart = hwaClone(st);
   hwaEnemyRound(st,hwaAIContext(B));
   hwa.predNext = st;
   hwa.predBoard = B;
};
_global.hwaCheckPrediction = function(B)
{
   // compare the predicted board with the real one, counting only armies the enemy round changed
   // (moved, fought, merged or spawned): the share of those that were predicted exactly
   var P = hwa.predNext;
   var O = hwa.predStart;
   hwa.predNext = null;
   if(!P || hwa.predBoard != B || !hwa.S || hwa.S.board != B)
   {
      return undefined;
   }
   var A = hwaRootState(B);
   var tot = 0;
   var ok = 0;
   var i = 0;
   while(i < hwa.S.n)
   {
      if((A.ap[i] >= 0 || P.ap[i] >= 0) && (A.ap[i] != O.ap[i] || A.ac[i] != O.ac[i] || P.ap[i] != O.ap[i] || P.ac[i] != O.ac[i]))
      {
         tot++;
         if(A.ap[i] == P.ap[i] && A.ac[i] == P.ac[i])
         {
            ok++;
         }
      }
      i++;
   }
   if(tot)
   {
      hwa.predAcc = hwa.predN != 0 ? 0.6 * hwa.predAcc + 0.4 * (ok / tot) : ok / tot;
      hwa.predN++;
   }
};
_global.hwaBoard = function()
{
   var B = _root.game_board;
   if(!B || B.hw_init || B.human == undefined || !B.hw_parties_armies)
   {
      return null;
   }
   return B;
};
_global.hwaMyTurn = function(B)
{
   return B && B.turn_party == B.human && B.hw_parties_control[B.human] == "human" && B.move_points > 0 && B.win == undefined && B.hw_parties_status[B.human] != 0;
};
_global.hwaDoPlanStep = function(B)
{
   if(!hwaMyTurn(B) || hwa.thinking || !hwa.plan.length || hwa.S.board != B)
   {
      return false;
   }
   var d = hwa.plan[0];
   if(d.code < 0)
   {
      if(d.code == -1 && !B.hw_parties_speech_given[B.human])
      {
         addMoraleForAll(50,B.human,B);
         B.hw_parties_speech_given[B.human] = true;
         B._parent.give_speech.inactive(true);
         playSound("s_blop",100,"other");
      }
      else if(d.code <= -10 && !B.hw_pact_signed)
      {
         if(signPact(- d.code - 10,B))
         {
            B.hw_pact_signed = true;
            B._parent.sign_pact.inactive(true);
            playSound("s_blop",100,"other");
         }
         else
         {
            hwa.sig = "";
            return false;
         }
      }
      else
      {
         hwa.sig = "";
         return false;
      }
      hwa.plan.shift();
      hwa.keepPlan = true;
      return true;
   }
   var sf = hwa.S.fld[d.s];
   var tf = hwa.S.fld[d.t];
   var a = sf.army;
   var ok = false;
   if(a && a.party == B.human && !a.moved && a.remove_time < 0)
   {
      var legal = getPossibleMoves(sf,true,false);
      var i = 0;
      while(i < legal.length)
      {
         if(legal[i] == tf)
         {
            ok = true;
         }
         i++;
      }
   }
   if(!ok)
   {
      hwa.sig = "";
      return false;
   }
   playSound("s_blop",100,"other");
   moveArmy(a,tf);
   B.selected_army = null;
   selectFields(getMovableArmies(B.turn_party,B),B);
   B.move_points--;
   hwa.plan.shift();
   hwa.keepPlan = true;
   return true;
};
_global.hwaPt = function(B, f)
{
   var p = {x:f._x,y:f._y};
   B.localToGlobal(p);
   _root.globalToLocal(p);
   return p;
};
_global.hwaCircle = function(mc, x, y, r)
{
   mc.moveTo(x + r,y);
   var i = 1;
   var ang;
   while(i <= 20)
   {
      ang = i / 20 * 3.141592653589793 * 2;
      mc.lineTo(x + Math.cos(ang) * r,y + Math.sin(ang) * r);
      i++;
   }
};
_global.hwaDraw = function(B)
{
   // arrows for the next 3 steps (gold = next, white = later) and a crosshair on the aggressive-mode target
   var o = _root.createEmptyMovieClip("hwa_overlay",1048000);
   if(!hwa.show || !B || !hwaMyTurn(B) || hwa.thinking || !hwa.S || hwa.S.board != B)
   {
      return undefined;
   }
   var i = 0;
   var p;
   if(hwa.aggr && hwa.target >= 0)
   {
      p = hwaPt(B,hwa.S.fld[hwa.S.capF[hwa.target]]);
      o.lineStyle(3,16750899,100);
      hwaCircle(o,p.x,p.y,24);
      o.lineStyle(2,16750899,70);
      hwaCircle(o,p.x,p.y,30);
      o.moveTo(p.x - 34,p.y);
      o.lineTo(p.x - 24,p.y);
      o.moveTo(p.x + 24,p.y);
      o.lineTo(p.x + 34,p.y);
      o.moveTo(p.x,p.y - 34);
      o.lineTo(p.x,p.y - 24);
      o.moveTo(p.x,p.y + 24);
      o.lineTo(p.x,p.y + 34);
   }
   i = Math.min(3,hwa.plan.length) - 1;
   var d;
   var a;
   var b;
   var dx;
   var dy;
   var len;
   var ux;
   var uy;
   var sx;
   var sy;
   var ex;
   var ey;
   var col;
   var w;
   var tf;
   while(i >= 0)
   {
      d = hwa.plan[i];
      if(d.code < 0)
      {
         i--;
         continue;
      }
      a = hwaPt(B,hwa.S.fld[d.s]);
      b = hwaPt(B,hwa.S.fld[d.t]);
      dx = b.x - a.x;
      dy = b.y - a.y;
      len = Math.sqrt(dx * dx + dy * dy);
      if(len < 1)
      {
         len = 1;
      }
      ux = dx / len;
      uy = dy / len;
      sx = a.x + ux * 8;
      sy = a.y + uy * 8;
      ex = b.x - ux * 6;
      ey = b.y - uy * 6;
      col = i != 0 ? 16777215 : 16766720;
      w = i != 0 ? 3 : 5;
      o.lineStyle(w + 3,0,45);
      o.moveTo(sx,sy);
      o.lineTo(ex,ey);
      o.moveTo(ex,ey);
      o.lineTo(ex - ux * 13 - uy * 8,ey - uy * 13 + ux * 8);
      o.moveTo(ex,ey);
      o.lineTo(ex - ux * 13 + uy * 8,ey - uy * 13 - ux * 8);
      o.lineStyle(w,col,100);
      o.moveTo(sx,sy);
      o.lineTo(ex,ey);
      o.moveTo(ex,ey);
      o.lineTo(ex - ux * 13 - uy * 8,ey - uy * 13 + ux * 8);
      o.moveTo(ex,ey);
      o.lineTo(ex - ux * 13 + uy * 8,ey - uy * 13 - ux * 8);
      o.createTextField("n" + i,10 + i,(sx + ex) / 2 - 12,(sy + ey) / 2 - 11,24,22);
      tf = o["n" + i];
      tf.selectable = false;
      tf.html = true;
      tf.background = true;
      tf.backgroundColor = 0;
      tf.htmlText = "<p align=\'center\'><font face=\'_sans\' size=\'13\' color=\'" + (i != 0 ? "#FFFFFF" : "#FFD700") + "\'><b>" + (i + 1) + "</b></font></p>";
      i--;
   }
};
_global.hwaStrip = function(str)
{
   // drop html tags so notes can be shown as plain short text
   var out = "";
   var inTag = false;
   var i = 0;
   var ch;
   while(i < str.length)
   {
      ch = str.charAt(i);
      if(ch == "<")
      {
         inTag = true;
      }
      else if(ch == ">")
      {
         inTag = false;
      }
      else if(!inTag)
      {
         out += ch;
      }
      i++;
   }
   return out;
};
_global.hwaConfColor = function(c)
{
   if(c >= 80)
   {
      return "#8FBF8F";
   }
   if(c >= 55)
   {
      return "#C8B070";
   }
   return "#C88070";
};
_global.hwaRender = function(B)
{
   var tf = _root.hwa_panel.txt;
   var s = "<font face=\'_sans\' size=\'12\' color=\'#DDDDDD\'>";
   s += "<font size=\'13\' color=\'#F2D27A\'><b>Hex Helper</b></font>";
   if(!B)
   {
      s += "\n<font color=\'#888888\'>Start a game to get advice.</font>";
   }
   else if(!hwaMyTurn(B))
   {
      s += "\n<font color=\'#888888\'>Waiting for your turn...</font>";
   }
   else if(hwa.thinking)
   {
      s += "\n<font color=\'#888888\'>Thinking... " + (hwa.job.stage != 0 ? "replaying enemy replies " + hwa.job.ri + "/" + hwa.job.pool.length : "planning " + (hwa.job.depth + 1) + " move" + (hwa.job.depth != 0 ? "s" : "") + " ahead") + "</font>";
   }
   else
   {
      s += "  <font color=\'#888888\'>turn " + B.turns + " · " + B.move_points + " move" + (B.move_points != 1 ? "s" : "") + " left" + (!hwa.auto ? "" : " · auto") + "</font>\n";
      if(hwa.aggr)
      {
         if(hwa.tgtInfo)
         {
            var T = hwa.tgtInfo;
            s += "<font color=\'#E8A060\'>Target: " + hwa.S.names[hwa.target] + " - ";
            if(T.now >= 1)
            {
               s += "can take " + hwa.S.fld[hwa.S.capF[hwa.target]].town_name + " now";
            }
            else if(T.att)
            {
               s += T.att + " in range (" + T.reach + " vs " + T.def + ")";
            }
            else
            {
               s += T.dist + " hexes away";
            }
            s += "</font>\n";
         }
         else
         {
            s += "<font color=\'#E8A060\'>Target: none left</font>\n";
         }
      }
      if(hwa.det0.capital)
      {
         s += "<font color=\'#FF7070\'>Capital exposed if you pass</font>\n";
      }
      var i = 0;
      var d;
      var notes;
      var j;
      var shownSteps = Math.min(3,hwa.plan.length);
      while(i < shownSteps)
      {
         d = hwa.plan[i];
         notes = "";
         j = 0;
         while(j < d.notes.length && j < 2)
         {
            notes += (j != 0 ? ", " : "") + hwaStrip(d.notes[j]);
            j++;
         }
         if(d.code < 0)
         {
            s += "<font color=\'" + (i != 0 ? "#DDDDDD" : "#F2D27A") + "\'>" + (i + 1) + "  " + (d.code != -1 ? "Sign a pact with " + hwa.S.names[- d.code - 10] : "Give a speech") + "</font>";
         }
         else
         {
            s += "<font color=\'" + (i != 0 ? "#DDDDDD" : "#F2D27A") + "\'>" + (i + 1) + "  " + hwaFieldName(hwa.S.fld[d.s]) + " " + d.count + " &gt; " + hwaFieldName(hwa.S.fld[d.t]) + "</font>";
         }
         s += " <font size=\'11\' color=\'" + hwaConfColor(d.conf) + "\'>" + d.conf + "%</font>";
         s += "<font size=\'11\' color=\'#999999\'>  " + (!notes.length ? d.kind : notes) + "</font>\n";
         i++;
      }
      if(hwa.plan.length > shownSteps)
      {
         s += "<font size=\'11\' color=\'#777777\'>+" + (hwa.plan.length - shownSteps) + " more after these</font>\n";
      }
      else if(hwa.endEarly)
      {
         s += "<font color=\'#9FC4E8\'>" + (!hwa.plan.length ? "E" : "then e") + "nd turn</font>\n";
      }
      if(hwa.predict)
      {
         var e = null;
         var hits = 0;
         i = 0;
         while(i < hwa.predict.length)
         {
            if(hwa.predict[i].took)
            {
               hits++;
               if(!e)
               {
                  e = hwa.predict[i];
               }
            }
            i++;
         }
         s += "<font size=\'11\' color=\'#999999\'>Replies" + (!hwa.predN ? "" : " <font color=\'" + hwaConfColor(Math.round(hwa.predAcc * 100)) + "\'>" + Math.round(hwa.predAcc * 100) + "%</font>") + ": ";
         if(hwa.capLost)
         {
            s += "<font color=\'#FF7070\'>your capital falls</font>";
         }
         else if(!e)
         {
            s += "nothing lost";
         }
         else
         {
            s += hwa.S.names[e.q] + (!e.army ? " takes " : " beats you at ") + hwaFieldName(hwa.S.fld[e.t]) + (hits <= 1 ? "" : " (+" + (hits - 1) + " more)");
         }
         s += "</font>\n";
      }
      s += "<font size=\'11\' color=\'#777777\'>income " + hwa.det0.inc + " &gt; " + hwa.det1.inc + " · power " + hwa.det0.power + " &gt; " + hwa.det1.power + " · " + Math.round(hwa.thinkTime / 100) / 10 + "s</font>";
   }
   s += "</font>";
   tf.htmlText = s;
   var btn = _root.hwa_panel.mode;
   btn.txt.htmlText = "<font face=\'_sans\' size=\'11\' color=\'#BBBBBB\'>mode: " + (!hwa.aggr ? "normal" : "aggressive") + "</font>";
   btn.bg.clear();
   btn.bg.lineStyle(1,5592405,100);
   btn.bg.beginFill(2236962,100);
   btn.bg.moveTo(0,0);
   btn.bg.lineTo(btn.txt._width + 8,0);
   btn.bg.lineTo(btn.txt._width + 8,btn.txt._height + 4);
   btn.bg.lineTo(0,btn.txt._height + 4);
   btn.bg.lineTo(0,0);
   btn.bg.endFill();
   btn._x = 6;
   btn._y = tf._height + 6;
   var keys = _root.hwa_panel.keys;
   keys.htmlText = "<font face=\'_sans\' size=\'10\' color=\'#666666\'>N next · A auto · E end · M mode · H hide</font>";
   keys._x = btn._x + btn._width + 8;
   keys._y = btn._y + 2;
   var w = Math.max(tf._width,keys._x + keys._width) + 10;
   var h = btn._y + btn._height + 5;
   var bg = _root.hwa_panel.bg;
   bg.clear();
   bg.lineStyle(1,6710886,80);
   bg.beginFill(0,80);
   bg.moveTo(0,0);
   bg.lineTo(w,0);
   bg.lineTo(w,h);
   bg.lineTo(0,h);
   bg.lineTo(0,0);
   bg.endFill();
};
_global.hwaToggleMode = function()
{
   hwa.aggr = !hwa.aggr;
   hwa.target = -1;
   hwa.sig = "";
   hwa.keepPlan = false;
   hwa.auto = false;
   var B = hwaBoard();
   hwaRender(B);
   hwaDraw(B);
};
_global.hwaHover = function(B)
{
   // with an army selected, preview what each destination is worth
   var tip = _root.hwa_tip;
   tip._visible = false;
   if(!hwa.show || !B || !hwaMyTurn(B) || !B.selected_army || hwa.thinking || !hwa.S || hwa.S.board != B)
   {
      return undefined;
   }
   var sel = B.selected_army;
   var i;
   var d;
   if(hwa.selKey != sel + "|" + hwa.sig)
   {
      hwa.selKey = sel + "|" + hwa.sig;
      hwa.selMoves = new Array();
      var root = hwaRootState(B);
      var base = hwaEval(root,null);
      var s = sel.field.hwa_i;
      var r = hwaReach(root,s);
      var ch;
      i = 0;
      while(i < r.length)
      {
         ch = hwaClone(root);
         d = {kind:"move",notes:new Array(),f:hwa.S.fld[r[i]]};
         hwaApply(ch,s,r[i],d);
         d.score = Math.round(hwaEval(ch,null) - base);
         hwa.selMoves.push(d);
         i++;
      }
      hwa.selMoves.sort(hwaByScore);
   }
   i = 0;
   while(i < hwa.selMoves.length)
   {
      d = hwa.selMoves[i];
      if(d.f.over)
      {
         tip.txt.htmlText = "<font face=\'_sans\' size=\'12\' color=\'#FFFFFF\'><b>" + d.kind.toUpperCase() + "</b>  <font color=\'" + (d.score < 0 ? "#FF6666" : "#66FF66") + "\'>" + (d.score < 0 ? "" : "+") + d.score + "</font> <font color=\'#999999\'>(#" + (i + 1) + " of " + hwa.selMoves.length + " for this army)</font>" + (!d.notes.length ? "" : "\n" + d.notes.join("\n")) + "</font>";
         tip.bg.clear();
         tip.bg.beginFill(0,85);
         tip.bg.lineStyle(1,16777215,60);
         tip.bg.moveTo(0,0);
         tip.bg.lineTo(tip.txt._width + 8,0);
         tip.bg.lineTo(tip.txt._width + 8,tip.txt._height + 4);
         tip.bg.lineTo(0,tip.txt._height + 4);
         tip.bg.lineTo(0,0);
         tip.bg.endFill();
         tip._x = Math.min(_root._xmouse + 18,790 - tip._width);
         tip._y = Math.min(_root._ymouse + 18,590 - tip._height);
         tip._visible = true;
         return undefined;
      }
      i++;
   }
};
_global.hwaMakeBox = function(name, depth)
{
   var mc = _root.createEmptyMovieClip(name,depth);
   mc.createEmptyMovieClip("bg",1);
   mc.createTextField("txt",2,6,4,10,10);
   mc.txt.autoSize = "left";
   mc.txt.html = true;
   mc.txt.multiline = true;
   mc.txt.wordWrap = false;
   mc.txt.selectable = false;
   return mc;
};
_global.hwaTick = function()
{
   // the game sets board.win only when a match ends; clear any leftover value while a new map is set up
   if(_root.game_board.hw_init && _root.game_board.win != undefined)
   {
      _root.game_board.win = undefined;
   }
   var B = hwaBoard();
   var my = hwaMyTurn(B);
   if(B && B.turn_party == B.human && B.win == undefined)
   {
      if(hwa.predNext)
      {
         hwaCheckPrediction(B);
      }
      hwa.awaitSnap = true;
   }
   else if(B && hwa.awaitSnap && B.win == undefined && B.hw_parties_status[B.human] != 0)
   {
      hwa.awaitSnap = false;
      hwaSnapshotPrediction(B);
   }
   var sig = "none";
   if(my)
   {
      sig = B.turn_party + "|" + B.move_points + "|" + B.turns + "|" + B.hw_lAID + "|" + B.hw_parties_total_power.join(",") + "|" + B.hw_peace + "|" + B.hw_parties_speech_given[B.human] + B.hw_pact_signed;
   }
   else if(B)
   {
      sig = "wait";
   }
   if(sig != hwa.sig)
   {
      hwa.sig = sig;
      if(my)
      {
         if(hwa.keepPlan && hwa.S && hwa.S.board == B)
         {
            // we just played a step of our own plan; the rest of it is still valid
            hwa.keepPlan = false;
            if(!hwa.plan.length && !hwa.endEarly)
            {
               hwaStartSearch(B);
            }
         }
         else
         {
            hwa.keepPlan = false;
            hwaStartSearch(B);
         }
      }
      else
      {
         hwa.job = null;
         hwa.thinking = false;
         hwa.plan = new Array();
         hwa.danger = new Array();
         hwa.keepPlan = false;
      }
      hwaRender(B);
      hwaDraw(B);
   }
   if(hwa.job)
   {
      var t0 = getTimer();
      while(!hwa.job.done && getTimer() - t0 < 28)
      {
         hwaStep();
         if(hwa.job.stage == 0 && getTimer() - hwa.job.t0 > HWA_TIME * 0.6)
         {
            hwa.job.cut = true;
            hwa.job.stage = 1;
         }
         else if(hwa.job.stage == 1 && getTimer() - hwa.job.t0 > HWA_TIME)
         {
            hwa.job.cut = true;
            hwaPickReranked(hwa.job);
            hwa.job.done = true;
         }
      }
      if(hwa.job.done)
      {
         hwaFinish();
         hwaDraw(B);
      }
      hwaRender(B);
   }
   _root.hwa_panel._visible = hwa.show;
   hwaHover(B);
   if(hwa.auto)
   {
      if(my)
      {
         if(!hwa.thinking && --hwa.autoWait <= 0)
         {
            hwa.autoWait = 15;
            if(hwa.plan.length)
            {
               hwaDoPlanStep(B);
            }
            else if(hwa.endEarly)
            {
               B.move_points = 0;
               hwa.auto = false;
            }
         }
      }
      else
      {
         hwa.auto = false;
         hwaRender(B);
      }
   }
};
if(!_global.hwa)
{
   _global.hwa = {show:true,auto:false,autoWait:0,sig:"",plan:new Array(),danger:new Array(),thinking:false,job:null,keepPlan:false,endEarly:false,aggr:false,target:-1,level:3,predN:0,predAcc:0,predNext:null,awaitSnap:false};
   var hwaPanel = hwaMakeBox("hwa_panel",1048001);
   hwaPanel._x = 8;
   hwaPanel._y = 8;
   // drag the panel by its background; the mode button sits on top and gets its own clicks
   hwaPanel.bg.onPress = function()
   {
      this._parent.startDrag();
   };
   hwaPanel.bg.onRelease = hwaPanel.bg.onReleaseOutside = function()
   {
      this._parent.stopDrag();
   };
   hwaPanel.bg.useHandCursor = false;
   hwaPanel.createTextField("keys",4,0,0,10,10);
   hwaPanel.keys.autoSize = "left";
   hwaPanel.keys.html = true;
   hwaPanel.keys.selectable = false;
   var hwaBtn = hwaPanel.createEmptyMovieClip("mode",3);
   hwaBtn.createEmptyMovieClip("bg",1);
   hwaBtn.createTextField("txt",2,4,2,10,10);
   hwaBtn.txt.autoSize = "left";
   hwaBtn.txt.html = true;
   hwaBtn.txt.selectable = false;
   hwaBtn.onRelease = function()
   {
      hwaToggleMode();
   };
   var hwaTip = hwaMakeBox("hwa_tip",1048002);
   hwaTip._visible = false;
   var hwaCtl = _root.createEmptyMovieClip("hwa_ctl",1048003);
   hwaCtl.onEnterFrame = function()
   {
      hwaTick();
   };
   var hwaKeys = new Object();
   hwaKeys.onKeyDown = function()
   {
      var c = Key.getCode();
      var B = hwaBoard();
      if(c == 72)
      {
         hwa.show = !hwa.show;
         hwaRender(B);
         hwaDraw(B);
      }
      else if(c == 78)
      {
         hwaDoPlanStep(B);
      }
      else if(c == 65)
      {
         hwa.auto = !hwa.auto && hwaMyTurn(B);
         hwa.autoWait = 0;
         hwaRender(B);
      }
      else if(c == 69)
      {
         if(hwaMyTurn(B))
         {
            B.move_points = 0;
         }
      }
      else if(c == 77)
      {
         hwaToggleMode();
      }
   };
   Key.addListener(hwaKeys);
}
// ===================== END MOD: NEXT BEST MOVE ADVISOR =====================

var He=Object.defineProperty;var Re=(r,e,t)=>e in r?He(r,e,{enumerable:!0,configurable:!0,writable:!0,value:t}):r[e]=t;var f=(r,e,t)=>Re(r,typeof e!="symbol"?e+"":e,t);(function(){const e=document.createElement("link").relList;if(e&&e.supports&&e.supports("modulepreload"))return;for(const n of document.querySelectorAll('link[rel="modulepreload"]'))s(n);new MutationObserver(n=>{for(const a of n)if(a.type==="childList")for(const i of a.addedNodes)i.tagName==="LINK"&&i.rel==="modulepreload"&&s(i)}).observe(document,{childList:!0,subtree:!0});function t(n){const a={};return n.integrity&&(a.integrity=n.integrity),n.referrerPolicy&&(a.referrerPolicy=n.referrerPolicy),n.crossOrigin==="use-credentials"?a.credentials="include":n.crossOrigin==="anonymous"?a.credentials="omit":a.credentials="same-origin",a}function s(n){if(n.ep)return;n.ep=!0;const a=t(n);fetch(n.href,a)}})();class ze{constructor(e=""){f(this,"baseUrl");this.baseUrl=e}async fetch(e,t){const s=await fetch(`${this.baseUrl}${e}`,{...t,headers:{"Content-Type":"application/json",...t==null?void 0:t.headers}});if(!s.ok)throw new Error(`API error: ${s.statusText}`);return s.json()}async getHealth(){return this.fetch("/api/admin/health")}async getTelemetry(e=14){return this.fetch(`/api/admin/telemetry?days=${e}`)}async getRedisKeys(){return this.fetch("/api/admin/redis/keys")}async getRedisKey(e){return this.fetch(`/api/admin/redis/key/${encodeURIComponent(e)}`)}async getDataGaps(){return this.fetch("/api/admin/data-gaps")}async getLeagueStats(e){return this.fetch(`/api/admin/leagues/${e}/stats`)}async getSchedules(){return this.fetch("/v2025/schedules")}async getTeams(){return this.fetch("/v2025/teams")}async getLiveGames(){return this.fetch("/v2025/all-live-games?cfb=1")}async invalidateKey(e){return this.fetch(`/api/admin/redis/invalidate/${encodeURIComponent(e)}`,{method:"POST"})}async refreshSchedules(){return this.fetch("/api/admin/redis/refresh",{method:"POST"})}async forceRefresh(){return this.fetch("/api/admin/force-refresh",{method:"POST"})}async triggerJob(e){return this.fetch(`/api/admin/jobs/trigger/${e}`,{method:"POST"})}async clearAllCache(){return this.fetch("/api/admin/cache/all",{method:"DELETE"})}async getPushToStartRegistrations(){return this.fetch("/api/admin/push-to-start/registrations")}async getPushToStartDiagnostics(){return this.fetch("/api/admin/push-to-start/diagnostics")}async triggerDebugPushToStart(e,t,s){return this.fetch("/v2025/debug/trigger-push-to-start",{method:"POST",body:JSON.stringify({eventID:e,homeTeam:t,awayTeam:s})})}}const _=new ze;class Oe{constructor(e="ws://localhost:8080/ws?cfb=1"){f(this,"ws",null);f(this,"reconnectTimer",null);f(this,"reconnectDelay",5e3);f(this,"url");f(this,"onMessageCallback",null);f(this,"onStatusChange",null);this.url=e}connect(e,t){var s;this.onMessageCallback=e,this.onStatusChange=t||null;try{const n=window.location.protocol==="https:"?this.url.replace("ws://","wss://"):this.url;this.ws=new WebSocket(n),this.ws.onopen=()=>{var a;console.log("WebSocket connected"),(a=this.onStatusChange)==null||a.call(this,!0),this.reconnectTimer&&(clearTimeout(this.reconnectTimer),this.reconnectTimer=null)},this.ws.onmessage=a=>{var i;try{const o=JSON.parse(a.data);(i=this.onMessageCallback)==null||i.call(this,o)}catch(o){console.error("Failed to parse WebSocket message:",o)}},this.ws.onerror=a=>{var i;console.error("WebSocket error:",a),(i=this.onStatusChange)==null||i.call(this,!1)},this.ws.onclose=()=>{var a;console.log("WebSocket disconnected"),(a=this.onStatusChange)==null||a.call(this,!1),this.scheduleReconnect()}}catch(n){console.error("Failed to connect WebSocket:",n),(s=this.onStatusChange)==null||s.call(this,!1),this.scheduleReconnect()}}scheduleReconnect(){this.reconnectTimer||(this.reconnectTimer=setTimeout(()=>{console.log("Attempting to reconnect WebSocket..."),this.onMessageCallback&&this.connect(this.onMessageCallback,this.onStatusChange||void 0)},this.reconnectDelay))}disconnect(){this.reconnectTimer&&(clearTimeout(this.reconnectTimer),this.reconnectTimer=null),this.ws&&(this.ws.close(),this.ws=null)}isConnected(){var e;return((e=this.ws)==null?void 0:e.readyState)===WebSocket.OPEN}}function k(r){const e=Object.prototype.toString.call(r);return r instanceof Date||typeof r=="object"&&e==="[object Date]"?new r.constructor(+r):typeof r=="number"||e==="[object Number]"||typeof r=="string"||e==="[object String]"?new Date(r):new Date(NaN)}function R(r,e){return r instanceof Date?new r.constructor(e):new Date(e)}const ke=6048e5,We=864e5,J=43200,me=1440;let Ne={};function U(){return Ne}function q(r,e){var o,l,c,d;const t=U(),s=(e==null?void 0:e.weekStartsOn)??((l=(o=e==null?void 0:e.locale)==null?void 0:o.options)==null?void 0:l.weekStartsOn)??t.weekStartsOn??((d=(c=t.locale)==null?void 0:c.options)==null?void 0:d.weekStartsOn)??0,n=k(r),a=n.getDay(),i=(a<s?7:0)+a-s;return n.setDate(n.getDate()-i),n.setHours(0,0,0,0),n}function ee(r){return q(r,{weekStartsOn:1})}function Le(r){const e=k(r),t=e.getFullYear(),s=R(r,0);s.setFullYear(t+1,0,4),s.setHours(0,0,0,0);const n=ee(s),a=R(r,0);a.setFullYear(t,0,4),a.setHours(0,0,0,0);const i=ee(a);return e.getTime()>=n.getTime()?t+1:e.getTime()>=i.getTime()?t:t-1}function ge(r){const e=k(r);return e.setHours(0,0,0,0),e}function te(r){const e=k(r),t=new Date(Date.UTC(e.getFullYear(),e.getMonth(),e.getDate(),e.getHours(),e.getMinutes(),e.getSeconds(),e.getMilliseconds()));return t.setUTCFullYear(e.getFullYear()),+r-+t}function Ie(r,e){const t=ge(r),s=ge(e),n=+t-te(t),a=+s-te(s);return Math.round((n-a)/We)}function Be(r){const e=Le(r),t=R(r,0);return t.setFullYear(e,0,4),t.setHours(0,0,0,0),ee(t)}function Z(r,e){const t=k(r),s=k(e),n=t.getTime()-s.getTime();return n<0?-1:n>0?1:n}function je(r){return R(r,Date.now())}function Ge(r){return r instanceof Date||typeof r=="object"&&Object.prototype.toString.call(r)==="[object Date]"}function qe(r){if(!Ge(r)&&typeof r!="number")return!1;const e=k(r);return!isNaN(Number(e))}function Ue(r,e){const t=k(r),s=k(e),n=t.getFullYear()-s.getFullYear(),a=t.getMonth()-s.getMonth();return n*12+a}function Ye(r){return e=>{const s=(r?Math[r]:Math.trunc)(e);return s===0?0:s}}function Ke(r,e){return+k(r)-+k(e)}function Xe(r){const e=k(r);return e.setHours(23,59,59,999),e}function Je(r){const e=k(r),t=e.getMonth();return e.setFullYear(e.getFullYear(),t+1,0),e.setHours(23,59,59,999),e}function Ve(r){const e=k(r);return+Xe(e)==+Je(e)}function Qe(r,e){const t=k(r),s=k(e),n=Z(t,s),a=Math.abs(Ue(t,s));let i;if(a<1)i=0;else{t.getMonth()===1&&t.getDate()>27&&t.setDate(30),t.setMonth(t.getMonth()-n*a);let o=Z(t,s)===-n;Ve(k(r))&&a===1&&Z(r,s)===1&&(o=!1),i=n*(a-Number(o))}return i===0?0:i}function Ze(r,e,t){const s=Ke(r,e)/1e3;return Ye(t==null?void 0:t.roundingMethod)(s)}function et(r){const e=k(r),t=R(r,0);return t.setFullYear(e.getFullYear(),0,1),t.setHours(0,0,0,0),t}const tt={lessThanXSeconds:{one:"less than a second",other:"less than {{count}} seconds"},xSeconds:{one:"1 second",other:"{{count}} seconds"},halfAMinute:"half a minute",lessThanXMinutes:{one:"less than a minute",other:"less than {{count}} minutes"},xMinutes:{one:"1 minute",other:"{{count}} minutes"},aboutXHours:{one:"about 1 hour",other:"about {{count}} hours"},xHours:{one:"1 hour",other:"{{count}} hours"},xDays:{one:"1 day",other:"{{count}} days"},aboutXWeeks:{one:"about 1 week",other:"about {{count}} weeks"},xWeeks:{one:"1 week",other:"{{count}} weeks"},aboutXMonths:{one:"about 1 month",other:"about {{count}} months"},xMonths:{one:"1 month",other:"{{count}} months"},aboutXYears:{one:"about 1 year",other:"about {{count}} years"},xYears:{one:"1 year",other:"{{count}} years"},overXYears:{one:"over 1 year",other:"over {{count}} years"},almostXYears:{one:"almost 1 year",other:"almost {{count}} years"}},st=(r,e,t)=>{let s;const n=tt[r];return typeof n=="string"?s=n:e===1?s=n.one:s=n.other.replace("{{count}}",e.toString()),t!=null&&t.addSuffix?t.comparison&&t.comparison>0?"in "+s:s+" ago":s};function re(r){return(e={})=>{const t=e.width?String(e.width):r.defaultWidth;return r.formats[t]||r.formats[r.defaultWidth]}}const rt={full:"EEEE, MMMM do, y",long:"MMMM do, y",medium:"MMM d, y",short:"MM/dd/yyyy"},nt={full:"h:mm:ss a zzzz",long:"h:mm:ss a z",medium:"h:mm:ss a",short:"h:mm a"},at={full:"{{date}} 'at' {{time}}",long:"{{date}} 'at' {{time}}",medium:"{{date}}, {{time}}",short:"{{date}}, {{time}}"},it={date:re({formats:rt,defaultWidth:"full"}),time:re({formats:nt,defaultWidth:"full"}),dateTime:re({formats:at,defaultWidth:"full"})},ot={lastWeek:"'last' eeee 'at' p",yesterday:"'yesterday at' p",today:"'today at' p",tomorrow:"'tomorrow at' p",nextWeek:"eeee 'at' p",other:"P"},lt=(r,e,t,s)=>ot[r];function B(r){return(e,t)=>{const s=t!=null&&t.context?String(t.context):"standalone";let n;if(s==="formatting"&&r.formattingValues){const i=r.defaultFormattingWidth||r.defaultWidth,o=t!=null&&t.width?String(t.width):i;n=r.formattingValues[o]||r.formattingValues[i]}else{const i=r.defaultWidth,o=t!=null&&t.width?String(t.width):r.defaultWidth;n=r.values[o]||r.values[i]}const a=r.argumentCallback?r.argumentCallback(e):e;return n[a]}}const ct={narrow:["B","A"],abbreviated:["BC","AD"],wide:["Before Christ","Anno Domini"]},dt={narrow:["1","2","3","4"],abbreviated:["Q1","Q2","Q3","Q4"],wide:["1st quarter","2nd quarter","3rd quarter","4th quarter"]},ht={narrow:["J","F","M","A","M","J","J","A","S","O","N","D"],abbreviated:["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"],wide:["January","February","March","April","May","June","July","August","September","October","November","December"]},ut={narrow:["S","M","T","W","T","F","S"],short:["Su","Mo","Tu","We","Th","Fr","Sa"],abbreviated:["Sun","Mon","Tue","Wed","Thu","Fri","Sat"],wide:["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]},mt={narrow:{am:"a",pm:"p",midnight:"mi",noon:"n",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"},abbreviated:{am:"AM",pm:"PM",midnight:"midnight",noon:"noon",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"},wide:{am:"a.m.",pm:"p.m.",midnight:"midnight",noon:"noon",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"}},gt={narrow:{am:"a",pm:"p",midnight:"mi",noon:"n",morning:"in the morning",afternoon:"in the afternoon",evening:"in the evening",night:"at night"},abbreviated:{am:"AM",pm:"PM",midnight:"midnight",noon:"noon",morning:"in the morning",afternoon:"in the afternoon",evening:"in the evening",night:"at night"},wide:{am:"a.m.",pm:"p.m.",midnight:"midnight",noon:"noon",morning:"in the morning",afternoon:"in the afternoon",evening:"in the evening",night:"at night"}},pt=(r,e)=>{const t=Number(r),s=t%100;if(s>20||s<10)switch(s%10){case 1:return t+"st";case 2:return t+"nd";case 3:return t+"rd"}return t+"th"},ft={ordinalNumber:pt,era:B({values:ct,defaultWidth:"wide"}),quarter:B({values:dt,defaultWidth:"wide",argumentCallback:r=>r-1}),month:B({values:ht,defaultWidth:"wide"}),day:B({values:ut,defaultWidth:"wide"}),dayPeriod:B({values:mt,defaultWidth:"wide",formattingValues:gt,defaultFormattingWidth:"wide"})};function j(r){return(e,t={})=>{const s=t.width,n=s&&r.matchPatterns[s]||r.matchPatterns[r.defaultMatchWidth],a=e.match(n);if(!a)return null;const i=a[0],o=s&&r.parsePatterns[s]||r.parsePatterns[r.defaultParseWidth],l=Array.isArray(o)?vt(o,m=>m.test(i)):yt(o,m=>m.test(i));let c;c=r.valueCallback?r.valueCallback(l):l,c=t.valueCallback?t.valueCallback(c):c;const d=e.slice(i.length);return{value:c,rest:d}}}function yt(r,e){for(const t in r)if(Object.prototype.hasOwnProperty.call(r,t)&&e(r[t]))return t}function vt(r,e){for(let t=0;t<r.length;t++)if(e(r[t]))return t}function bt(r){return(e,t={})=>{const s=e.match(r.matchPattern);if(!s)return null;const n=s[0],a=e.match(r.parsePattern);if(!a)return null;let i=r.valueCallback?r.valueCallback(a[0]):a[0];i=t.valueCallback?t.valueCallback(i):i;const o=e.slice(n.length);return{value:i,rest:o}}}const wt=/^(\d+)(th|st|nd|rd)?/i,$t=/\d+/i,xt={narrow:/^(b|a)/i,abbreviated:/^(b\.?\s?c\.?|b\.?\s?c\.?\s?e\.?|a\.?\s?d\.?|c\.?\s?e\.?)/i,wide:/^(before christ|before common era|anno domini|common era)/i},St={any:[/^b/i,/^(a|c)/i]},Tt={narrow:/^[1234]/i,abbreviated:/^q[1234]/i,wide:/^[1234](th|st|nd|rd)? quarter/i},kt={any:[/1/i,/2/i,/3/i,/4/i]},Lt={narrow:/^[jfmasond]/i,abbreviated:/^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i,wide:/^(january|february|march|april|may|june|july|august|september|october|november|december)/i},Ct={narrow:[/^j/i,/^f/i,/^m/i,/^a/i,/^m/i,/^j/i,/^j/i,/^a/i,/^s/i,/^o/i,/^n/i,/^d/i],any:[/^ja/i,/^f/i,/^mar/i,/^ap/i,/^may/i,/^jun/i,/^jul/i,/^au/i,/^s/i,/^o/i,/^n/i,/^d/i]},Et={narrow:/^[smtwf]/i,short:/^(su|mo|tu|we|th|fr|sa)/i,abbreviated:/^(sun|mon|tue|wed|thu|fri|sat)/i,wide:/^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)/i},Pt={narrow:[/^s/i,/^m/i,/^t/i,/^w/i,/^t/i,/^f/i,/^s/i],any:[/^su/i,/^m/i,/^tu/i,/^w/i,/^th/i,/^f/i,/^sa/i]},Mt={narrow:/^(a|p|mi|n|(in the|at) (morning|afternoon|evening|night))/i,any:/^([ap]\.?\s?m\.?|midnight|noon|(in the|at) (morning|afternoon|evening|night))/i},At={any:{am:/^a/i,pm:/^p/i,midnight:/^mi/i,noon:/^no/i,morning:/morning/i,afternoon:/afternoon/i,evening:/evening/i,night:/night/i}},Dt={ordinalNumber:bt({matchPattern:wt,parsePattern:$t,valueCallback:r=>parseInt(r,10)}),era:j({matchPatterns:xt,defaultMatchWidth:"wide",parsePatterns:St,defaultParseWidth:"any"}),quarter:j({matchPatterns:Tt,defaultMatchWidth:"wide",parsePatterns:kt,defaultParseWidth:"any",valueCallback:r=>r+1}),month:j({matchPatterns:Lt,defaultMatchWidth:"wide",parsePatterns:Ct,defaultParseWidth:"any"}),day:j({matchPatterns:Et,defaultMatchWidth:"wide",parsePatterns:Pt,defaultParseWidth:"any"}),dayPeriod:j({matchPatterns:Mt,defaultMatchWidth:"any",parsePatterns:At,defaultParseWidth:"any"})},Ce={code:"en-US",formatDistance:st,formatLong:it,formatRelative:lt,localize:ft,match:Dt,options:{weekStartsOn:0,firstWeekContainsDate:1}};function _t(r){const e=k(r);return Ie(e,et(e))+1}function Ft(r){const e=k(r),t=+ee(e)-+Be(e);return Math.round(t/ke)+1}function Ee(r,e){var d,m,g,p;const t=k(r),s=t.getFullYear(),n=U(),a=(e==null?void 0:e.firstWeekContainsDate)??((m=(d=e==null?void 0:e.locale)==null?void 0:d.options)==null?void 0:m.firstWeekContainsDate)??n.firstWeekContainsDate??((p=(g=n.locale)==null?void 0:g.options)==null?void 0:p.firstWeekContainsDate)??1,i=R(r,0);i.setFullYear(s+1,0,a),i.setHours(0,0,0,0);const o=q(i,e),l=R(r,0);l.setFullYear(s,0,a),l.setHours(0,0,0,0);const c=q(l,e);return t.getTime()>=o.getTime()?s+1:t.getTime()>=c.getTime()?s:s-1}function Ht(r,e){var o,l,c,d;const t=U(),s=(e==null?void 0:e.firstWeekContainsDate)??((l=(o=e==null?void 0:e.locale)==null?void 0:o.options)==null?void 0:l.firstWeekContainsDate)??t.firstWeekContainsDate??((d=(c=t.locale)==null?void 0:c.options)==null?void 0:d.firstWeekContainsDate)??1,n=Ee(r,e),a=R(r,0);return a.setFullYear(n,0,s),a.setHours(0,0,0,0),q(a,e)}function Rt(r,e){const t=k(r),s=+q(t,e)-+Ht(t,e);return Math.round(s/ke)+1}function T(r,e){const t=r<0?"-":"",s=Math.abs(r).toString().padStart(e,"0");return t+s}const H={y(r,e){const t=r.getFullYear(),s=t>0?t:1-t;return T(e==="yy"?s%100:s,e.length)},M(r,e){const t=r.getMonth();return e==="M"?String(t+1):T(t+1,2)},d(r,e){return T(r.getDate(),e.length)},a(r,e){const t=r.getHours()/12>=1?"pm":"am";switch(e){case"a":case"aa":return t.toUpperCase();case"aaa":return t;case"aaaaa":return t[0];case"aaaa":default:return t==="am"?"a.m.":"p.m."}},h(r,e){return T(r.getHours()%12||12,e.length)},H(r,e){return T(r.getHours(),e.length)},m(r,e){return T(r.getMinutes(),e.length)},s(r,e){return T(r.getSeconds(),e.length)},S(r,e){const t=e.length,s=r.getMilliseconds(),n=Math.trunc(s*Math.pow(10,t-3));return T(n,e.length)}},N={midnight:"midnight",noon:"noon",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"},pe={G:function(r,e,t){const s=r.getFullYear()>0?1:0;switch(e){case"G":case"GG":case"GGG":return t.era(s,{width:"abbreviated"});case"GGGGG":return t.era(s,{width:"narrow"});case"GGGG":default:return t.era(s,{width:"wide"})}},y:function(r,e,t){if(e==="yo"){const s=r.getFullYear(),n=s>0?s:1-s;return t.ordinalNumber(n,{unit:"year"})}return H.y(r,e)},Y:function(r,e,t,s){const n=Ee(r,s),a=n>0?n:1-n;if(e==="YY"){const i=a%100;return T(i,2)}return e==="Yo"?t.ordinalNumber(a,{unit:"year"}):T(a,e.length)},R:function(r,e){const t=Le(r);return T(t,e.length)},u:function(r,e){const t=r.getFullYear();return T(t,e.length)},Q:function(r,e,t){const s=Math.ceil((r.getMonth()+1)/3);switch(e){case"Q":return String(s);case"QQ":return T(s,2);case"Qo":return t.ordinalNumber(s,{unit:"quarter"});case"QQQ":return t.quarter(s,{width:"abbreviated",context:"formatting"});case"QQQQQ":return t.quarter(s,{width:"narrow",context:"formatting"});case"QQQQ":default:return t.quarter(s,{width:"wide",context:"formatting"})}},q:function(r,e,t){const s=Math.ceil((r.getMonth()+1)/3);switch(e){case"q":return String(s);case"qq":return T(s,2);case"qo":return t.ordinalNumber(s,{unit:"quarter"});case"qqq":return t.quarter(s,{width:"abbreviated",context:"standalone"});case"qqqqq":return t.quarter(s,{width:"narrow",context:"standalone"});case"qqqq":default:return t.quarter(s,{width:"wide",context:"standalone"})}},M:function(r,e,t){const s=r.getMonth();switch(e){case"M":case"MM":return H.M(r,e);case"Mo":return t.ordinalNumber(s+1,{unit:"month"});case"MMM":return t.month(s,{width:"abbreviated",context:"formatting"});case"MMMMM":return t.month(s,{width:"narrow",context:"formatting"});case"MMMM":default:return t.month(s,{width:"wide",context:"formatting"})}},L:function(r,e,t){const s=r.getMonth();switch(e){case"L":return String(s+1);case"LL":return T(s+1,2);case"Lo":return t.ordinalNumber(s+1,{unit:"month"});case"LLL":return t.month(s,{width:"abbreviated",context:"standalone"});case"LLLLL":return t.month(s,{width:"narrow",context:"standalone"});case"LLLL":default:return t.month(s,{width:"wide",context:"standalone"})}},w:function(r,e,t,s){const n=Rt(r,s);return e==="wo"?t.ordinalNumber(n,{unit:"week"}):T(n,e.length)},I:function(r,e,t){const s=Ft(r);return e==="Io"?t.ordinalNumber(s,{unit:"week"}):T(s,e.length)},d:function(r,e,t){return e==="do"?t.ordinalNumber(r.getDate(),{unit:"date"}):H.d(r,e)},D:function(r,e,t){const s=_t(r);return e==="Do"?t.ordinalNumber(s,{unit:"dayOfYear"}):T(s,e.length)},E:function(r,e,t){const s=r.getDay();switch(e){case"E":case"EE":case"EEE":return t.day(s,{width:"abbreviated",context:"formatting"});case"EEEEE":return t.day(s,{width:"narrow",context:"formatting"});case"EEEEEE":return t.day(s,{width:"short",context:"formatting"});case"EEEE":default:return t.day(s,{width:"wide",context:"formatting"})}},e:function(r,e,t,s){const n=r.getDay(),a=(n-s.weekStartsOn+8)%7||7;switch(e){case"e":return String(a);case"ee":return T(a,2);case"eo":return t.ordinalNumber(a,{unit:"day"});case"eee":return t.day(n,{width:"abbreviated",context:"formatting"});case"eeeee":return t.day(n,{width:"narrow",context:"formatting"});case"eeeeee":return t.day(n,{width:"short",context:"formatting"});case"eeee":default:return t.day(n,{width:"wide",context:"formatting"})}},c:function(r,e,t,s){const n=r.getDay(),a=(n-s.weekStartsOn+8)%7||7;switch(e){case"c":return String(a);case"cc":return T(a,e.length);case"co":return t.ordinalNumber(a,{unit:"day"});case"ccc":return t.day(n,{width:"abbreviated",context:"standalone"});case"ccccc":return t.day(n,{width:"narrow",context:"standalone"});case"cccccc":return t.day(n,{width:"short",context:"standalone"});case"cccc":default:return t.day(n,{width:"wide",context:"standalone"})}},i:function(r,e,t){const s=r.getDay(),n=s===0?7:s;switch(e){case"i":return String(n);case"ii":return T(n,e.length);case"io":return t.ordinalNumber(n,{unit:"day"});case"iii":return t.day(s,{width:"abbreviated",context:"formatting"});case"iiiii":return t.day(s,{width:"narrow",context:"formatting"});case"iiiiii":return t.day(s,{width:"short",context:"formatting"});case"iiii":default:return t.day(s,{width:"wide",context:"formatting"})}},a:function(r,e,t){const n=r.getHours()/12>=1?"pm":"am";switch(e){case"a":case"aa":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"});case"aaa":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"}).toLowerCase();case"aaaaa":return t.dayPeriod(n,{width:"narrow",context:"formatting"});case"aaaa":default:return t.dayPeriod(n,{width:"wide",context:"formatting"})}},b:function(r,e,t){const s=r.getHours();let n;switch(s===12?n=N.noon:s===0?n=N.midnight:n=s/12>=1?"pm":"am",e){case"b":case"bb":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"});case"bbb":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"}).toLowerCase();case"bbbbb":return t.dayPeriod(n,{width:"narrow",context:"formatting"});case"bbbb":default:return t.dayPeriod(n,{width:"wide",context:"formatting"})}},B:function(r,e,t){const s=r.getHours();let n;switch(s>=17?n=N.evening:s>=12?n=N.afternoon:s>=4?n=N.morning:n=N.night,e){case"B":case"BB":case"BBB":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"});case"BBBBB":return t.dayPeriod(n,{width:"narrow",context:"formatting"});case"BBBB":default:return t.dayPeriod(n,{width:"wide",context:"formatting"})}},h:function(r,e,t){if(e==="ho"){let s=r.getHours()%12;return s===0&&(s=12),t.ordinalNumber(s,{unit:"hour"})}return H.h(r,e)},H:function(r,e,t){return e==="Ho"?t.ordinalNumber(r.getHours(),{unit:"hour"}):H.H(r,e)},K:function(r,e,t){const s=r.getHours()%12;return e==="Ko"?t.ordinalNumber(s,{unit:"hour"}):T(s,e.length)},k:function(r,e,t){let s=r.getHours();return s===0&&(s=24),e==="ko"?t.ordinalNumber(s,{unit:"hour"}):T(s,e.length)},m:function(r,e,t){return e==="mo"?t.ordinalNumber(r.getMinutes(),{unit:"minute"}):H.m(r,e)},s:function(r,e,t){return e==="so"?t.ordinalNumber(r.getSeconds(),{unit:"second"}):H.s(r,e)},S:function(r,e){return H.S(r,e)},X:function(r,e,t){const s=r.getTimezoneOffset();if(s===0)return"Z";switch(e){case"X":return ye(s);case"XXXX":case"XX":return z(s);case"XXXXX":case"XXX":default:return z(s,":")}},x:function(r,e,t){const s=r.getTimezoneOffset();switch(e){case"x":return ye(s);case"xxxx":case"xx":return z(s);case"xxxxx":case"xxx":default:return z(s,":")}},O:function(r,e,t){const s=r.getTimezoneOffset();switch(e){case"O":case"OO":case"OOO":return"GMT"+fe(s,":");case"OOOO":default:return"GMT"+z(s,":")}},z:function(r,e,t){const s=r.getTimezoneOffset();switch(e){case"z":case"zz":case"zzz":return"GMT"+fe(s,":");case"zzzz":default:return"GMT"+z(s,":")}},t:function(r,e,t){const s=Math.trunc(r.getTime()/1e3);return T(s,e.length)},T:function(r,e,t){const s=r.getTime();return T(s,e.length)}};function fe(r,e=""){const t=r>0?"-":"+",s=Math.abs(r),n=Math.trunc(s/60),a=s%60;return a===0?t+String(n):t+String(n)+e+T(a,2)}function ye(r,e){return r%60===0?(r>0?"-":"+")+T(Math.abs(r)/60,2):z(r,e)}function z(r,e=""){const t=r>0?"-":"+",s=Math.abs(r),n=T(Math.trunc(s/60),2),a=T(s%60,2);return t+n+e+a}const ve=(r,e)=>{switch(r){case"P":return e.date({width:"short"});case"PP":return e.date({width:"medium"});case"PPP":return e.date({width:"long"});case"PPPP":default:return e.date({width:"full"})}},Pe=(r,e)=>{switch(r){case"p":return e.time({width:"short"});case"pp":return e.time({width:"medium"});case"ppp":return e.time({width:"long"});case"pppp":default:return e.time({width:"full"})}},zt=(r,e)=>{const t=r.match(/(P+)(p+)?/)||[],s=t[1],n=t[2];if(!n)return ve(r,e);let a;switch(s){case"P":a=e.dateTime({width:"short"});break;case"PP":a=e.dateTime({width:"medium"});break;case"PPP":a=e.dateTime({width:"long"});break;case"PPPP":default:a=e.dateTime({width:"full"});break}return a.replace("{{date}}",ve(s,e)).replace("{{time}}",Pe(n,e))},Ot={p:Pe,P:zt},Wt=/^D+$/,Nt=/^Y+$/,It=["D","DD","YY","YYYY"];function Bt(r){return Wt.test(r)}function jt(r){return Nt.test(r)}function Gt(r,e,t){const s=qt(r,e,t);if(console.warn(s),It.includes(r))throw new RangeError(s)}function qt(r,e,t){const s=r[0]==="Y"?"years":"days of the month";return`Use \`${r.toLowerCase()}\` instead of \`${r}\` (in \`${e}\`) for formatting ${s} to the input \`${t}\`; see: https://github.com/date-fns/date-fns/blob/master/docs/unicodeTokens.md`}const Ut=/[yYQqMLwIdDecihHKkms]o|(\w)\1*|''|'(''|[^'])+('|$)|./g,Yt=/P+p+|P+|p+|''|'(''|[^'])+('|$)|./g,Kt=/^'([^]*?)'?$/,Xt=/''/g,Jt=/[a-zA-Z]/;function Vt(r,e,t){var d,m,g,p;const s=U(),n=s.locale??Ce,a=s.firstWeekContainsDate??((m=(d=s.locale)==null?void 0:d.options)==null?void 0:m.firstWeekContainsDate)??1,i=s.weekStartsOn??((p=(g=s.locale)==null?void 0:g.options)==null?void 0:p.weekStartsOn)??0,o=k(r);if(!qe(o))throw new RangeError("Invalid time value");let l=e.match(Yt).map(h=>{const u=h[0];if(u==="p"||u==="P"){const b=Ot[u];return b(h,n.formatLong)}return h}).join("").match(Ut).map(h=>{if(h==="''")return{isToken:!1,value:"'"};const u=h[0];if(u==="'")return{isToken:!1,value:Qt(h)};if(pe[u])return{isToken:!0,value:h};if(u.match(Jt))throw new RangeError("Format string contains an unescaped latin alphabet character `"+u+"`");return{isToken:!1,value:h}});n.localize.preprocessor&&(l=n.localize.preprocessor(o,l));const c={firstWeekContainsDate:a,weekStartsOn:i,locale:n};return l.map(h=>{if(!h.isToken)return h.value;const u=h.value;(jt(u)||Bt(u))&&Gt(u,e,String(r));const b=pe[u[0]];return b(o,u,n.localize,c)}).join("")}function Qt(r){const e=r.match(Kt);return e?e[1].replace(Xt,"'"):r}function Zt(r,e,t){const s=U(),n=(t==null?void 0:t.locale)??s.locale??Ce,a=2520,i=Z(r,e);if(isNaN(i))throw new RangeError("Invalid time value");const o=Object.assign({},t,{addSuffix:t==null?void 0:t.addSuffix,comparison:i});let l,c;i>0?(l=k(e),c=k(r)):(l=k(r),c=k(e));const d=Ze(c,l),m=(te(c)-te(l))/1e3,g=Math.round((d-m)/60);let p;if(g<2)return t!=null&&t.includeSeconds?d<5?n.formatDistance("lessThanXSeconds",5,o):d<10?n.formatDistance("lessThanXSeconds",10,o):d<20?n.formatDistance("lessThanXSeconds",20,o):d<40?n.formatDistance("halfAMinute",0,o):d<60?n.formatDistance("lessThanXMinutes",1,o):n.formatDistance("xMinutes",1,o):g===0?n.formatDistance("lessThanXMinutes",1,o):n.formatDistance("xMinutes",g,o);if(g<45)return n.formatDistance("xMinutes",g,o);if(g<90)return n.formatDistance("aboutXHours",1,o);if(g<me){const h=Math.round(g/60);return n.formatDistance("aboutXHours",h,o)}else{if(g<a)return n.formatDistance("xDays",1,o);if(g<J){const h=Math.round(g/me);return n.formatDistance("xDays",h,o)}else if(g<J*2)return p=Math.round(g/J),n.formatDistance("aboutXMonths",p,o)}if(p=Qe(c,l),p<12){const h=Math.round(g/J);return n.formatDistance("xMonths",h,o)}else{const h=p%12,u=Math.trunc(p/12);return h<3?n.formatDistance("aboutXYears",u,o):h<9?n.formatDistance("overXYears",u,o):n.formatDistance("almostXYears",u+1,o)}}function es(r,e){return Zt(r,je(r),e)}function be(r){if(!r)return"N/A";const e=["B","KB","MB","GB"];let t=r,s=0;for(;t>=1024&&s<e.length-1;)t/=1024,s++;return`${t.toFixed(2)} ${e[s]}`}function ne(r){if(!r)return"Never";try{const e=new Date(r);return es(e,{addSuffix:!0})}catch{return"Invalid date"}}function V(r){if(!r)return"N/A";try{const e=new Date(r);return Vt(e,"MMM d, yyyy HH:mm:ss")}catch{return"Invalid date"}}function we(r){if(r==null||r<0)return"No expiration";const e=Math.floor(r/3600),t=Math.floor(r%3600/60),s=r%60;return e>0?`${e}h ${t}m ${s}s`:t>0?`${t}m ${s}s`:`${s}s`}function $e(r){return`${(r*100).toFixed(1)}%`}function O(r){if(!r)return{text:"Unknown",class:"badge"};const e=r.toLowerCase();return["ft","aot","final","post","completed","finished","match finished"].some(t=>e.includes(t))?{text:"Final",class:"badge info"}:["ns","pre","scheduled","not started"].some(t=>e.includes(t))?{text:"Upcoming",class:"badge warning"}:["live","active","in progress","in play"].some(t=>e.includes(t))||/^\d/.test(e)?{text:"Live",class:"badge success"}:{text:r,class:"badge"}}function $(r,e="success"){const t=document.createElement("div");t.className=`toast ${e}`,t.textContent=r,document.body.appendChild(t),setTimeout(()=>{t.remove()},5e3)}function ts(r){try{const e=JSON.parse(r);return ae(e,0)}catch{return r.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}}function ae(r,e){const t="  ".repeat(e),s="  ".repeat(e+1);if(r===null)return'<span class="json-null">null</span>';if(typeof r=="boolean")return`<span class="json-boolean">${r}</span>`;if(typeof r=="number")return`<span class="json-number">${r}</span>`;if(typeof r=="string")return`<span class="json-string">"${r.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;")}"</span>`;if(Array.isArray(r)){if(r.length===0)return'<span class="json-punctuation">[]</span>';const n=`collapse-${Math.random().toString(36).substr(2,9)}`,a=r.length===1?"1 item":`${r.length} items`;let i='<span class="json-punctuation">[</span>';return i+=`<span class="json-collapse-btn" data-target="${n}" style="cursor: pointer; color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem;">▼ ${a}</span>`,i+=`
<div id="${n}" class="json-collapsible">`,r.forEach((o,l)=>{i+=s,i+=ae(o,e+1),l<r.length-1&&(i+='<span class="json-punctuation">,</span>'),i+=`
`}),i+=`</div>${t}<span class="json-punctuation">]</span>`,i}if(typeof r=="object"){const n=Object.keys(r);if(n.length===0)return'<span class="json-punctuation">{}</span>';const a=`collapse-${Math.random().toString(36).substr(2,9)}`,i=n.length===1?"1 property":`${n.length} properties`;let o='<span class="json-punctuation">{</span>';return o+=`<span class="json-collapse-btn" data-target="${a}" style="cursor: pointer; color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem;">▼ ${i}</span>`,o+=`
<div id="${a}" class="json-collapsible">`,n.forEach((l,c)=>{const d=l.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");o+=s,o+=`<span class="json-key">"${d}"</span><span class="json-punctuation">: </span>`,o+=ae(r[l],e+1),c<n.length-1&&(o+='<span class="json-punctuation">,</span>'),o+=`
`}),o+=`</div>${t}<span class="json-punctuation">}</span>`,o}return String(r)}class ss{constructor(){f(this,"logContainer",null);f(this,"logs",[]);f(this,"maxLogs",50);this.createLogContainer()}createLogContainer(){var t,s;const e=document.createElement("div");e.id="connection-log",e.style.cssText=`
      position: fixed;
      bottom: 1rem;
      right: 1rem;
      width: 400px;
      max-height: 300px;
      background: var(--surface-color);
      border: 1px solid var(--border-color);
      border-radius: 0.5rem;
      box-shadow: var(--shadow-lg);
      z-index: 1000;
      display: none;
      flex-direction: column;
    `,e.innerHTML=`
      <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.75rem; border-bottom: 1px solid var(--border-color);">
        <span style="font-weight: 600; font-size: 0.875rem;">Connection Log</span>
        <div>
          <button id="clear-log" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; margin-right: 0.5rem; border: 1px solid var(--border-color); background: var(--surface-color); border-radius: 0.25rem; cursor: pointer;">Clear</button>
          <button id="close-log" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; border: 1px solid var(--border-color); background: var(--surface-color); border-radius: 0.25rem; cursor: pointer;">Close</button>
        </div>
      </div>
      <div id="log-content" style="padding: 0.75rem; overflow-y: auto; flex: 1; font-family: monospace; font-size: 0.75rem;"></div>
    `,document.body.appendChild(e),this.logContainer=e,(t=document.getElementById("clear-log"))==null||t.addEventListener("click",()=>this.clear()),(s=document.getElementById("close-log"))==null||s.addEventListener("click",()=>this.hide()),this.addToggleButton()}addToggleButton(){const e=document.querySelector(".header");if(e){const t=document.createElement("button");t.textContent="📋 Log",t.style.cssText=`
        padding: 0.5rem 1rem;
        border: 1px solid var(--border-color);
        background: var(--surface-color);
        border-radius: 0.375rem;
        cursor: pointer;
        font-size: 0.875rem;
      `,t.addEventListener("click",()=>this.toggle()),e.appendChild(t)}}log(e,t="info"){const s=new Date().toLocaleTimeString(),n={info:"var(--text-secondary)",success:"var(--success-color)",error:"var(--danger-color)",warning:"var(--warning-color)"}[t],a=`[${s}] ${e}`;this.logs.push(a),this.logs.length>this.maxLogs&&this.logs.shift();const i=document.getElementById("log-content");if(i){const o=document.createElement("div");o.style.color=n,o.textContent=a,i.appendChild(o),i.scrollTop=i.scrollHeight}console.log(`[ConnectionLog] ${a}`)}clear(){this.logs=[];const e=document.getElementById("log-content");e&&(e.innerHTML="")}show(){this.logContainer&&(this.logContainer.style.display="flex")}hide(){this.logContainer&&(this.logContainer.style.display="none")}toggle(){this.logContainer&&(this.logContainer.style.display==="flex"?this.hide():this.show())}}const x=new ss;class rs{constructor(){f(this,"container",null);f(this,"intervalId",null);f(this,"lastFetchTime",null)}render(e){this.container=e,this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">System Health</h2>
          <button class="btn btn-primary" id="refresh-health" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="health-content" class="loading">Loading health status...</div>
      </div>
    `;const t=this.container.querySelector("#refresh-health");t==null||t.addEventListener("click",()=>this.manualRefresh()),x.log("Health Monitor initialized","info"),this.fetchHealthWithTimeout(),this.intervalId=setInterval(()=>this.fetchHealthWithTimeout(),1e4)}manualRefresh(){x.log("Manual refresh triggered","info"),$("Refreshing health status...","success"),this.fetchHealthWithTimeout()}stop(){this.intervalId&&(clearInterval(this.intervalId),this.intervalId=null)}async fetchHealthWithTimeout(){var t,s;const e=Date.now();x.log("Fetching health status from /api/admin/health...","info");try{const n=new Promise((l,c)=>setTimeout(()=>c(new Error("Request timeout after 5s")),5e3)),a=_.getHealth(),i=await Promise.race([a,n]),o=Date.now()-e;x.log(`Health status received in ${o}ms`,"success"),this.lastFetchTime=new Date,this.displayHealth(i)}catch(n){const a=Date.now()-e,i=n instanceof Error?n.message:"Unknown error";x.log(`Health fetch failed after ${a}ms: ${i}`,"error"),console.error("Failed to fetch health:",n);const o=(t=this.container)==null?void 0:t.querySelector("#health-content");o&&(o.innerHTML=`
          <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
            <div style="font-weight: 600; font-size: 1.125rem;">Failed to connect to API</div>
            <div style="color: var(--text-secondary); margin-top: 0.5rem; margin-bottom: 1rem;">
              Make sure the Vapor server is running on port 8080<br/>
              Error: ${i}
            </div>
            <button class="btn btn-primary" id="retry-health">🔄 Retry</button>
          </div>
        `,(s=o.querySelector("#retry-health"))==null||s.addEventListener("click",()=>this.manualRefresh())),$("Failed to fetch health status","error")}}displayHealth(e){var l;const t=(l=this.container)==null?void 0:l.querySelector("#health-content");if(!t)return;const s=e.status==="healthy",n=this.lastFetchTime?ne(this.lastFetchTime.toISOString()):"just now";t.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">System Health</h2>
          <span class="badge ${s?"success":"danger"}">
            ${e.status.toUpperCase()}
          </span>
        </div>
        <div class="grid grid-3">
          <div class="stat-card">
            <div class="stat-value">${e.redis.keyCount??"N/A"}</div>
            <div class="stat-label">Redis Keys</div>
          </div>
          <div class="stat-card">
            <div class="stat-value">${e.redis.memory??"N/A"}</div>
            <div class="stat-label">Memory Used</div>
          </div>
          <div class="stat-card">
            <div class="stat-value ${e.redis.connected?"success":"danger"}">${e.redis.connected?"Connected":"Disconnected"}</div>
            <div class="stat-label">Redis Status</div>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Background Jobs</h2>
        </div>
        <table>
          <thead>
            <tr>
              <th>Job Name</th>
              <th>Schedule</th>
              <th>Last Run</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            ${e.jobs.map(c=>{const d=["ESPNTeamFetchJob","ScheduleUpdateJob","ESPNFetchJob","ESPNCricketJob"].includes(c.name);return`
              <tr>
                <td>${c.name}</td>
                <td>${c.schedule}</td>
                <td>${ne(c.lastRun)}</td>
                <td><span class="badge ${c.status==="ok"?"success":c.status==="stale"?"danger":"warning"}">${c.status}</span></td>
                <td>${d?`<button class="btn btn-primary trigger-job-btn" data-job="${c.name}" style="padding: 0.25rem 0.75rem; font-size: 0.8rem;">Run Now</button>`:""}</td>
              </tr>`}).join("")}
          </tbody>
        </table>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Actions</h2>
        </div>
        <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
          <button class="btn btn-primary" id="force-refresh">Force Refresh All Schedules</button>
          <button class="btn btn-primary" id="refresh-schedules">Clear Schedule Cache</button>
          <button class="btn btn-danger" id="clear-cache">Clear All Cache</button>
        </div>
      </div>

      <div style="display: flex; justify-content: space-between; align-items: center; padding: 1rem; background: var(--bg-color); border-radius: 0.375rem; font-size: 0.875rem; color: var(--text-secondary);">
        <span>Last updated: ${n}</span>
        <span>Server time: ${ne(e.timestamp)}</span>
      </div>
    `;const a=t.querySelector("#force-refresh");a==null||a.addEventListener("click",()=>this.forceRefresh(a));const i=t.querySelector("#refresh-schedules");i==null||i.addEventListener("click",()=>this.refreshSchedules());const o=t.querySelector("#clear-cache");o==null||o.addEventListener("click",()=>this.clearCache()),t.querySelectorAll(".trigger-job-btn").forEach(c=>{c.addEventListener("click",d=>{const m=d.target.dataset.job;m&&this.triggerJob(m,d.target)})})}async forceRefresh(e){const t=e.textContent;e.disabled=!0,e.textContent="Refreshing...";try{const s=await _.forceRefresh(),n=Object.entries(s.gamesLoaded).filter(([,a])=>a>0).map(([a,i])=>`${a}: ${i}`).join(", ");$(`${s.message}${n?` (${n})`:""}`,"success"),this.fetchHealthWithTimeout()}catch{$("Failed to force refresh schedules","error")}finally{e.disabled=!1,e.textContent=t}}async refreshSchedules(){try{const e=await _.refreshSchedules();$(e.message,"success"),this.fetchHealthWithTimeout()}catch{$("Failed to refresh schedules","error")}}async triggerJob(e,t){const s=t.textContent;t.disabled=!0,t.textContent="Running...";try{const n=await _.triggerJob(e);$(n.message,n.success?"success":"error"),this.fetchHealthWithTimeout()}catch{$(`Failed to trigger ${e}`,"error")}finally{t.disabled=!1,t.textContent=s}}async clearCache(){if(confirm("Are you sure you want to clear ALL cache? This will delete all Redis keys."))try{const e=await _.clearAllCache();$(e.message,"success"),this.fetchHealthWithTimeout()}catch{$("Failed to clear cache","error")}}}class ns{constructor(){f(this,"container",null);f(this,"wsManager");f(this,"connectionStatus",null);f(this,"useWebSocket",!0);f(this,"refreshInterval",null);this.wsManager=new Oe,this.connectionStatus=document.getElementById("connection-status")}render(e){var t,s;this.container=e,x.log("Live Games initialized","info"),this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Live Games</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-primary" id="refresh-live" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
            <button class="btn btn-secondary" id="toggle-mode" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Mode</button>
            <span class="badge info" id="ws-status">Loading...</span>
          </div>
        </div>
        <div id="live-games-content" style="text-align: center; padding: 3rem; color: var(--text-secondary);">
          <div class="loading">Loading live games...</div>
        </div>
      </div>
    `,(t=this.container.querySelector("#refresh-live"))==null||t.addEventListener("click",()=>this.manualRefresh()),(s=this.container.querySelector("#toggle-mode"))==null||s.addEventListener("click",()=>this.toggleMode()),this.fetchLiveGames(),this.refreshInterval=setInterval(()=>this.fetchLiveGames(),1e4)}toggleMode(){this.useWebSocket=!this.useWebSocket,this.useWebSocket?(x.log("Switching to WebSocket mode","info"),$("Using WebSocket for live updates","success"),this.refreshInterval&&(clearInterval(this.refreshInterval),this.refreshInterval=null),this.wsManager.connect(e=>this.handleLiveData(e),e=>this.updateConnectionStatus(e))):(x.log("Switching to polling mode","info"),$("Using API polling (10s refresh)","success"),this.wsManager.disconnect(),this.refreshInterval||(this.refreshInterval=setInterval(()=>this.fetchLiveGames(),1e4)),this.fetchLiveGames())}async manualRefresh(){x.log("Manual refresh triggered","info"),$("Refreshing live games...","success"),await this.fetchLiveGames()}async fetchLiveGames(){var t,s;x.log("Fetching live games...","info");const e=Date.now();try{const n=new Promise((d,m)=>setTimeout(()=>m(new Error("Request timed out after 10s")),1e4)),a=fetch("/api/admin/live-espn").then(async d=>{if(!d.ok)throw new Error(`HTTP ${d.status}`);return d.json()}),i=await Promise.race([a,n]),o=Date.now()-e;x.log(`All games fetched in ${o}ms`,"success");const l=(d=[])=>d.filter(m=>{const g=m.strStatus||"";return g==="in"||/^(Q[1-4]|OT|Half|P[1-3])/.test(g)}),c={nba:i.nba?{events:l(i.nba.events)}:void 0,nfl:i.nfl?{events:l(i.nfl.events)}:void 0,nhl:i.nhl?{events:l(i.nhl.events)}:void 0,mlb:i.mlb?{events:l(i.mlb.events)}:void 0,soccer:i.soccer?{events:l(i.soccer.events)}:void 0,golf:i.golf?{events:l(i.golf.events)}:void 0,tennis:i.tennis?{events:l(i.tennis.events)}:void 0,racing:i.racing?{events:l(i.racing.events)}:void 0,motorsport:i.motorsport?{events:l(i.motorsport.events)}:void 0,cricket:i.cricket?{events:l(i.cricket.events)}:void 0};this.handleLiveData(c,i)}catch(n){const a=Date.now()-e,i=n instanceof Error?n.message:"Unknown error";x.log(`Failed to fetch live games after ${a}ms: ${i}`,"error");const o=(t=this.container)==null?void 0:t.querySelector("#live-games-content");o&&(o.innerHTML=`
          <div style="text-align: center; padding: 3rem;">
            <div style="font-size: 2rem; margin-bottom: 1rem; color: var(--danger-color);">Failed to load</div>
            <div style="color: var(--text-secondary); margin-bottom: 1rem;">${i}</div>
            <button class="btn btn-primary" id="retry-live">Retry</button>
          </div>
        `,(s=o.querySelector("#retry-live"))==null||s.addEventListener("click",()=>this.manualRefresh()))}}stop(){this.wsManager.disconnect(),this.updateConnectionStatus(!1),this.refreshInterval&&(clearInterval(this.refreshInterval),this.refreshInterval=null)}updateConnectionStatus(e){var s;this.connectionStatus&&(this.connectionStatus.className=`status-indicator ${e?"connected":"disconnected"}`);const t=(s=this.container)==null?void 0:s.querySelector("#ws-status");t&&(t.className=e?"badge success":"badge warning",t.textContent=e?"Connected":"Disconnected")}handleLiveData(e,t){var l,c;if(!this.container)return;const s=[{name:"NBA",data:e.nba,allData:t==null?void 0:t.nba,color:"#1d428a"},{name:"NFL",data:e.nfl,allData:t==null?void 0:t.nfl,color:"#013369"},{name:"NHL",data:e.nhl,allData:t==null?void 0:t.nhl,color:"#000000"},{name:"MLB",data:e.mlb,allData:t==null?void 0:t.mlb,color:"#002d72"},{name:"Soccer",data:e.soccer,allData:t==null?void 0:t.soccer,color:"#00a650"},{name:"Golf",data:e.golf,allData:t==null?void 0:t.golf,color:"#2ca58d"},{name:"Tennis",data:e.tennis,allData:t==null?void 0:t.tennis,color:"#c8b900"},{name:"Formula 1",data:e.racing,allData:t==null?void 0:t.racing,color:"#e10600"},{name:"NASCAR / IndyCar / IMSA / WEC",data:e.motorsport,allData:t==null?void 0:t.motorsport,color:"#ffd659"},{name:"Cricket",data:e.cricket,allData:t==null?void 0:t.cricket,color:"#1b7a3e"}],n=s.reduce((d,m)=>{var g,p;return d+(((p=(g=m.data)==null?void 0:g.events)==null?void 0:p.length)||0)},0),a=s.reduce((d,m)=>{var g,p;return d+(((p=(g=m.allData)==null?void 0:g.events)==null?void 0:p.length)||0)},0);x.log(`Displaying ${n} live games (${a} total)`,n>0?"success":"info");const i=(l=this.container)==null?void 0:l.querySelector("#live-games-content"),o=(c=this.container)==null?void 0:c.querySelector("#ws-status");if(o&&(o.className=`badge ${n>0?"success":"info"}`,o.textContent=`${n} Live${a>0?` / ${a} Total`:""}`),i){const d=s.filter(g=>{var p,h,u,b;return(((h=(p=g.allData)==null?void 0:p.events)==null?void 0:h.length)||0)>0||(((b=(u=g.data)==null?void 0:u.events)==null?void 0:b.length)||0)>0}).map(g=>{var u,b,E,A;const p=((b=(u=g.data)==null?void 0:u.events)==null?void 0:b.length)||0,h=((A=(E=g.allData)==null?void 0:E.events)==null?void 0:A.length)||0;return`<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.5rem 0; border-bottom: 1px solid var(--border-color);">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 4px; height: 24px; background: ${g.color}; border-radius: 2px;"></span>
              <span style="font-weight: 500;">${g.name}</span>
            </div>
            <div style="display: flex; gap: 0.5rem;">
              ${p>0?`<span class="badge success">${p} Live</span>`:""}
              <span class="badge info">${h} Games</span>
            </div>
          </div>`}).join(""),m=n>0?s.map(g=>this.renderSportSection(g.name,g.data,g.color)).join(""):"";i.innerHTML=`
        ${d?`
          <div style="margin-bottom: 1.5rem;">
            <h3 style="font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem; color: var(--text-secondary);">Live Scoreboard Summary</h3>
            ${d}
          </div>
        `:""}

        ${m||`
          <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
            <div style="font-weight: 600; margin-bottom: 0.5rem;">No live games at the moment</div>
            <div style="font-size: 0.875rem;">Auto-refreshing every 10 seconds</div>
          </div>
        `}
      `,i.querySelectorAll("[data-tournament-id]").forEach(g=>{g.addEventListener("click",p=>{if(p.target.closest("button, a"))return;const h=g.querySelector(".tournament-collapsed"),u=g.querySelector(".tournament-expanded");h&&u&&(h.classList.toggle("hidden"),u.classList.toggle("hidden"))})})}}renderSportSection(e,t,s){return!t||!t.events||t.events.length===0?"":`
      <div class="card">
        <div class="card-header" style="border-left: 4px solid ${s};">
          <h3 class="card-title">${e}</h3>
          <span class="badge info">${t.events.length} Games</span>
        </div>
        <div style="display: grid; gap: 1rem;">
          ${t.events.map(n=>this.renderGame(n,e)).join("")}
        </div>
      </div>
    `}renderGame(e,t){return t==="Golf"||t==="Tennis"||t==="Formula 1"||t.startsWith("NASCAR")?this.renderTournamentGame(e):this.renderTeamGame(e,t==="Cricket")}renderTeamGame(e,t=!1){const s=O(e.strStatus),n=t?"–":"0",a=e.intHomeScore||n,i=e.intAwayScore||n,o=t?"0.95rem":"1.25rem";return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span class="${s.class}">${s.text}</span>
          <span style="font-size: 0.875rem; color: var(--text-secondary);">${e.strProgress||""}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${e.strHomeTeamBadge?`<img src="${e.strHomeTeamBadge}" alt="${e.strHomeTeam}" style="width: 24px; height: 24px;">`:""}
            <span style="font-weight: 500;">${e.strHomeTeam}</span>
          </div>
          <span style="font-size: ${o}; font-weight: 700;">${a}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${e.strAwayTeamBadge?`<img src="${e.strAwayTeamBadge}" alt="${e.strAwayTeam}" style="width: 24px; height: 24px;">`:""}
            <span style="font-weight: 500;">${e.strAwayTeam}</span>
          </div>
          <span style="font-size: ${o}; font-weight: 700;">${i}</span>
        </div>
        ${e.aggregateScore||e.legDisplay?`
        <div style="margin-top: 0.5rem; font-size: 0.75rem; color: var(--text-secondary);">
          ${[e.legDisplay,e.aggregateScore].filter(Boolean).join(" · ")}
        </div>`:""}
        ${t&&e.lastPlay?`
        <div style="margin-top: 0.5rem; font-size: 0.75rem; color: var(--text-secondary);">${e.lastPlay}</div>`:""}
      </div>
    `}renderTournamentGame(e){const t=O(e.strStatus),s=e.idEvent||Math.random().toString(36).slice(2),n=(e.lastPlay||"").split(`
`).filter(m=>m.includes("|")).map((m,g)=>{const p=m.split("|"),h=p[0]||"TBD",u=p[1]||"--",b=p[2]?p[2].split(","):[];return{position:g+1,name:h,score:u,rounds:b}}),a=n.some(m=>m.rounds.length>0),i=Math.max(0,...n.map(m=>m.rounds.length)),o=n.length>0?n.slice(0,5).map(m=>`
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0; ${m.position===1?"font-weight: 600;":"color: var(--text-secondary);"}">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${m.position}</span>
              <span>${m.name}</span>
            </div>
            <span style="font-weight: 500;">${m.score}</span>
          </div>
        `).join(""):`<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0;">
            <span>${e.strAwayTeam}</span>
            <span style="font-weight: 600;">${e.intAwayScore||"--"}</span>
         </div>`,l=a?Array.from({length:i},(m,g)=>`<span style="width: 2.5rem; text-align: right; font-size: 0.75rem;">R${g+1}</span>`).join(""):"",c=n.map(m=>{const g=a?Array.from({length:i},(p,h)=>`<span style="width: 2.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${m.rounds[h]||"-"}</span>`).join(""):"";return`
        <div style="display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0; ${m.position===1?"font-weight: 600;":"color: var(--text-secondary);"}">
          <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${m.position}</span>
          <span style="flex: 1;">${m.name}</span>
          <span style="width: 3rem; text-align: right; font-weight: 500;">${m.score}</span>
          ${g}
        </div>
      `}).join(""),d=n.length>5;return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem; cursor: ${d?"pointer":"default"};" data-tournament-id="${s}">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span style="font-weight: 600; font-size: 1rem;">${e.strHomeTeam}</span>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            ${d?'<span style="font-size: 0.75rem; color: var(--text-secondary);">Click to expand</span>':""}
            <span class="${t.class}">${t.text}</span>
          </div>
        </div>
        ${e.strProgress?`<div style="font-size: 0.8rem; color: var(--text-secondary); margin-bottom: 0.5rem;">${e.strProgress}</div>`:""}
        <div class="tournament-collapsed" style="border-top: 1px solid var(--border-color); padding-top: 0.5rem;">
          ${o}
        </div>
        <div class="tournament-expanded hidden" style="border-top: 1px solid var(--border-color); padding-top: 0.5rem;">
          ${a?`
            <div style="display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0; font-size: 0.75rem; color: var(--text-secondary); border-bottom: 1px solid var(--border-color); margin-bottom: 0.25rem;">
              <span style="width: 1.5rem; text-align: right;">Pos</span>
              <span style="flex: 1;">Player</span>
              <span style="width: 3rem; text-align: right;">Score</span>
              ${l}
            </div>
          `:""}
          ${c}
        </div>
      </div>
    `}}const as=["espn","fifa","mlb-statsapi","nhl-apiweb","nba-cdn"];class is{constructor(){f(this,"container",null);f(this,"refreshInterval",null);f(this,"liveGames",[])}render(e){var t,s;this.container=e,this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Live Sources</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-secondary" id="ls-reset" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Reset Stats</button>
            <button class="btn btn-primary" id="ls-refresh" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Every source configured for a league is polled each tick; the copy furthest along in game time wins.
          A <em>win</em> is a score change a source reported before any other; <em>lag</em> is how long a source took to catch up
          to one it didn't report first (resolution is the tick interval).
        </p>
        <div id="ls-content"><div class="loading">Loading...</div></div>
      </div>
    `,(t=this.container.querySelector("#ls-refresh"))==null||t.addEventListener("click",()=>this.load()),(s=this.container.querySelector("#ls-reset"))==null||s.addEventListener("click",()=>this.resetStats()),this.load(),this.refreshInterval=setInterval(()=>this.load(),1e4)}stop(){this.refreshInterval&&(clearInterval(this.refreshInterval),this.refreshInterval=null)}async load(){var e;try{const[t,s]=await Promise.all([this.request("/api/admin/live-sources"),this.request("/api/admin/live-espn")]);this.liveGames=Object.values(s).flatMap(n=>(n==null?void 0:n.events)??[]).filter(n=>n.strStatus==="in"&&!!n.idEvent),this.renderContent(t)}catch(t){const s=(e=this.container)==null?void 0:e.querySelector("#ls-content");s&&(s.innerHTML=`<div class="badge error">${this.escapeHtml(t instanceof Error?t.message:"Failed to load")}</div>`)}}renderContent(e){var g,p;const t=(g=this.container)==null?void 0:g.querySelector("#ls-content");if(!t)return;const s=h=>{const u=this.liveGames.find(b=>b.idEvent===h);return u?`${u.strAwayTeam} @ ${u.strHomeTeam}`:h},n=h=>`${h.toFixed(1)}s`,a=e.sources.length?e.sources.map(h=>`
          <tr>
            <td style="font-family: monospace;">${this.escapeHtml(h.name)}</td>
            <td>${h.wins}</td>
            <td>${h.follows}</td>
            <td>${n(h.averageLagSeconds)}</td>
            <td>${n(h.maxLagSeconds)}</td>
            <td>${h.behind}</td>
          </tr>`).join(""):'<tr><td colspan="6" style="color: var(--text-secondary);">No contested score changes yet.</td></tr>',i=Object.entries(e.configured),o=i.length?i.map(([h,u])=>`${this.escapeHtml(h)}: ${u.map(b=>this.escapeHtml(b)).join(" + ")}`).join(" · "):"ESPN only (no LIVE_SOURCE_* overrides set)",l=Object.entries(e.forced).map(([h,u])=>`
        <tr>
          <td>${this.escapeHtml(s(h))} <span style="color: var(--text-secondary); font-family: monospace;">${this.escapeHtml(h)}</span></td>
          <td style="font-family: monospace;">${this.escapeHtml(u)}</td>
          <td><button class="btn btn-secondary ls-unpin" data-event="${this.escapeHtml(h)}" style="padding: 0.25rem 0.75rem; font-size: 0.8rem;">Unpin</button></td>
        </tr>`).join(""),c=this.liveGames.map(h=>`<option value="${this.escapeHtml(h.idEvent??"")}">${this.escapeHtml(`${h.strAwayTeam} @ ${h.strHomeTeam}`)}</option>`).join(""),d=as.map(h=>`<option value="${h}">${h}</option>`).join(""),m=e.recent.length?e.recent.map(h=>`
          <tr>
            <td>${this.escapeHtml(s(h.eventID))}</td>
            <td>${this.escapeHtml(h.score)}</td>
            <td style="font-family: monospace;">${this.escapeHtml(h.first)}</td>
            <td>${Object.entries(h.followers).map(([u,b])=>`${this.escapeHtml(u)} +${n(b)}`).join(", ")}</td>
            <td>${this.escapeHtml(new Date(h.at).toLocaleTimeString())}</td>
          </tr>`).join(""):'<tr><td colspan="5" style="color: var(--text-secondary);">None yet — needs two sources covering the same live game.</td></tr>';t.innerHTML=`
      <p style="margin-bottom: 1rem;">
        Tick: <strong>${e.tickIntervalSeconds}s</strong>
        · Since: <strong>${e.since?this.escapeHtml(new Date(e.since).toLocaleString()):"—"}</strong>
        · Sources: ${o}
      </p>
      <h3 style="margin: 1rem 0 0.5rem;">Sources</h3>
      <table>
        <thead><tr><th>Source</th><th>Wins</th><th>Follows</th><th>Avg lag</th><th>Max lag</th><th>Behind (dropped)</th></tr></thead>
        <tbody>${a}</tbody>
      </table>

      <h3 style="margin: 1.5rem 0 0.5rem;">Pinned games</h3>
      <div style="display: flex; gap: 0.5rem; align-items: center; margin-bottom: 0.75rem;">
        <select id="ls-game" style="padding: 0.45rem 0.75rem; border-radius: 0.375rem; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color);">
          ${c||'<option value="">No live games</option>'}
        </select>
        <select id="ls-source" style="padding: 0.45rem 0.75rem; border-radius: 0.375rem; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color);">
          ${d}
        </select>
        <button class="btn btn-primary" id="ls-pin" style="padding: 0.5rem 1rem; font-size: 0.875rem;" ${c?"":"disabled"}>Pin</button>
      </div>
      ${l?`<table><thead><tr><th>Game</th><th>Source</th><th></th></tr></thead><tbody>${l}</tbody></table>`:'<p style="color: var(--text-secondary);">No pins. A pinned game takes only that source, ahead or behind.</p>'}

      <h3 style="margin: 1.5rem 0 0.5rem;">Recent contested changes</h3>
      <table>
        <thead><tr><th>Game</th><th>Score</th><th>First</th><th>Followers</th><th>At</th></tr></thead>
        <tbody>${m}</tbody>
      </table>
    `,(p=t.querySelector("#ls-pin"))==null||p.addEventListener("click",()=>this.pin()),t.querySelectorAll(".ls-unpin").forEach(h=>{h.addEventListener("click",()=>{const u=h.dataset.event;u&&this.unpin(u)})})}async pin(){var s,n,a,i;const e=(n=(s=this.container)==null?void 0:s.querySelector("#ls-game"))==null?void 0:n.value,t=(i=(a=this.container)==null?void 0:a.querySelector("#ls-source"))==null?void 0:i.value;if(!(!e||!t))try{await this.request("/api/admin/live-sources/forced",{method:"PUT",body:JSON.stringify({eventID:e,source:t})}),$(`Pinned to ${t}`,"success"),this.load()}catch(o){$(o instanceof Error?o.message:"Pin failed","error")}}async unpin(e){try{await this.request(`/api/admin/live-sources/forced/${encodeURIComponent(e)}`,{method:"DELETE"}),$("Unpinned","success"),this.load()}catch(t){$(t instanceof Error?t.message:"Unpin failed","error")}}async resetStats(){try{await this.request("/api/admin/live-sources/stats",{method:"DELETE"},!1),$("Stats reset","success"),this.load()}catch(e){$(e instanceof Error?e.message:"Reset failed","error")}}async request(e,t,s=!0){const n=await fetch(e,{...t,headers:{"Content-Type":"application/json",...t==null?void 0:t.headers}});if(!n.ok)throw new Error(`HTTP ${n.status}`);return s?n.json():void 0}escapeHtml(e){return e.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;")}}var v=(r=>(r[r.English_Premier_League=4328]="English_Premier_League",r[r.English_League_Championship=4329]="English_League_Championship",r[r.German_Bundesliga=4331]="German_Bundesliga",r[r.Serie_A=4332]="Serie_A",r[r.Ligue_1=4334]="Ligue_1",r[r.La_Liga=4335]="La_Liga",r[r.Eredivisie=4337]="Eredivisie",r[r.MLS=4346]="MLS",r[r.Liga_MX=4350]="Liga_MX",r[r.A_League=4356]="A_League",r[r.FIFA_World_Cup=4429]="FIFA_World_Cup",r[r.UEFA_Champions_League=4480]="UEFA_Champions_League",r[r.UEFA_Europa_League=4481]="UEFA_Europa_League",r[r.FA_Cup=4482]="FA_Cup",r[r.Copa_del_Rey=4483]="Copa_del_Rey",r[r.Coupe_De_France=4484]="Coupe_De_France",r[r.DFB_Pokal=4485]="DFB_Pokal",r[r.UEFA_Nations_League=4490]="UEFA_Nations_League",r[r.Copa_America=4499]="Copa_America",r[r.UEFA_Conference_League=5071]="UEFA_Conference_League",r[r.Womens_World_Cup=4565]="Womens_World_Cup",r[r.NFL=4391]="NFL",r[r.NBA=4387]="NBA",r[r.NHL=4380]="NHL",r[r.MLB=4424]="MLB",r[r.PGA=4425]="PGA",r[r.ATP=4464]="ATP",r[r.WTA=4517]="WTA",r[r.Formula1=4370]="Formula1",r[r.NASCARCup=4393]="NASCARCup",r[r.IndyCar=4373]="IndyCar",r[r.IMSA=4488]="IMSA",r[r.WEC=4413]="WEC",r[r.CricketTests=4844]="CricketTests",r[r.CricketODIs=4801]="CricketODIs",r[r.CricketT20Is=4979]="CricketT20Is",r[r.WomensCricketInternationals=8201]="WomensCricketInternationals",r[r.IPL=4460]="IPL",r[r.BigBash=4461]="BigBash",r[r.PSL=5067]="PSL",r[r.SA20=5532]="SA20",r[r.TheHundred=5177]="TheHundred",r[r.CPL=5176]="CPL",r[r.MLC=5401]="MLC",r[r.ILT20=5490]="ILT20",r[r.WBBL=8202]="WBBL",r[r.TheHundredWomen=5668]="TheHundredWomen",r[r.SheffieldShield=5530]="SheffieldShield",r[r.CountyChampionship=4458]="CountyChampionship",r))(v||{});const xe=new Set([4844,4801,4979,8201,4460,4461,5067,5532,5177,5176,5401,5490,8202,5668,5530,4458]),G={4328:"English Premier League",4329:"English Championship",4331:"Bundesliga",4332:"Serie A",4334:"Ligue 1",4335:"La Liga",4337:"Eredivisie",4346:"MLS",4350:"Liga MX",4356:"A-League",4429:"FIFA World Cup",4480:"UEFA Champions League",4481:"UEFA Europa League",4482:"FA Cup",4483:"Copa Del Rey",4484:"Coupe De France",4485:"DFB Pokal",4490:"UEFA Nations League",4499:"Copa America",5071:"UEFA Conference League",4391:"NFL",4424:"MLB",4380:"NHL",4387:"NBA",4565:"FIFA Women's World Cup",4425:"PGA Tour",4464:"ATP Tour",4517:"WTA Tour",4370:"Formula 1",4393:"NASCAR Cup Series",4373:"IndyCar Series",4488:"IMSA WeatherTech",4413:"FIA WEC",4844:"Test Cricket",4801:"One-Day Internationals",4979:"T20 Internationals",8201:"Women's Internationals",4460:"Indian Premier League",4461:"Big Bash League",5067:"Pakistan Super League",5532:"SA20",5177:"The Hundred",5176:"Caribbean Premier League",5401:"Major League Cricket",5490:"ILT20",8202:"Women's Big Bash League",5668:"The Hundred (Women)",5530:"Sheffield Shield",4458:"County Championship"};class os{constructor(){f(this,"container",null);f(this,"leagueStats",new Map);f(this,"scheduleData",null);f(this,"currentFilter","all");f(this,"selectedLeague",null);f(this,"isLoading",!1);f(this,"selectedSeason","all");f(this,"selectedTeam","all");f(this,"expandedRaceSessions",new Set)}async render(e){this.container=e,x.log("League Explorer initialized","info"),this.showLoadingState(),await this.loadData()}showLoadingState(){this.container&&(this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
        </div>
        <div style="text-align: center; padding: 3rem; color: var(--text-secondary);">
          <div style="font-size: 2rem; margin-bottom: 1rem; animation: pulse 1.5s infinite;">Loading schedules...</div>
          <div style="font-size: 0.875rem;">Fetching data from server</div>
        </div>
      </div>
    `)}async loadData(){if(!this.isLoading){this.isLoading=!0,x.log("Fetching schedules from /v2025/schedules...","info");try{const e=Date.now(),t=new Promise((n,a)=>setTimeout(()=>a(new Error("Request timed out after 15s")),15e3));this.scheduleData=await Promise.race([_.getSchedules(),t]);const s=Date.now()-e;x.log(`Schedules loaded in ${s}ms`,"success"),this.computeAllStats(),this.displayAllLeagues()}catch(e){const t=e instanceof Error?e.message:"Unknown error";x.log(`Failed to fetch schedules: ${t}`,"error"),this.showErrorState(t)}finally{this.isLoading=!1}}}showErrorState(e){var t;this.container&&(this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
        </div>
        <div style="text-align: center; padding: 3rem;">
          <div style="font-size: 2rem; margin-bottom: 1rem; color: var(--danger-color);">Failed to load</div>
          <div style="color: var(--text-secondary); margin-bottom: 1.5rem;">${e}</div>
          <button class="btn btn-primary" id="retry-btn">Retry</button>
        </div>
      </div>
    `,(t=this.container.querySelector("#retry-btn"))==null||t.addEventListener("click",()=>{this.showLoadingState(),this.loadData()}))}stop(){}computeAllStats(){if(this.leagueStats.clear(),!this.scheduleData)return;const e=(s,n)=>{const a=new Set,i=this.isIndividualSport(n);let o=0,l=0,c=0;for(const d of s){if(i){if(d.strHomeTeam&&d.strHomeTeam!=="TBD"){const g=n===v.Formula1?this.extractGPName(d.strHomeTeam):d.strHomeTeam;a.add(g)}}else d.strHomeTeam&&a.add(d.strHomeTeam),d.strAwayTeam&&a.add(d.strAwayTeam);const m=(d.strStatus||"").toLowerCase();["ft","aot","final","final/ot","post","completed","finished","match finished","ap"].includes(m)?l++:["ns","pre","","scheduled","not started"].includes(m)?c++:o++}this.leagueStats.set(n,{league:G[n]||"Unknown",leagueId:n,sport:this.getSportForLeague(n),totalGames:s.length,liveGames:o,completedGames:l,upcomingGames:c,teams:Array.from(a).sort()})};if(this.scheduleData.nba&&e(this.scheduleData.nba.events,v.NBA),this.scheduleData.nfl&&e(this.scheduleData.nfl.events,v.NFL),this.scheduleData.nhl&&e(this.scheduleData.nhl.events,v.NHL),this.scheduleData.mlb&&e(this.scheduleData.mlb.events,v.MLB),this.scheduleData.golf&&e(this.scheduleData.golf.events,v.PGA),this.scheduleData.racing&&e(this.scheduleData.racing.events,v.Formula1),this.scheduleData.motorsport)for(const s of[v.NASCARCup,v.IndyCar,v.IMSA,v.WEC]){const n=this.scheduleData.motorsport.events.filter(a=>a.idLeague===String(s));n.length&&e(n,s)}const t=s=>{const n=new Map;for(const a of s){const i=parseInt(a.idLeague||"0");if(!i)continue;const o=n.get(i)||[];o.push(a),n.set(i,o)}return n};if(this.scheduleData.soccer){const s=t(this.scheduleData.soccer.events);for(const[n,a]of s){const i=n;G[i]&&e(a,i)}}if(this.scheduleData.tennis){const s=t(this.scheduleData.tennis.events);for(const[n,a]of s){const i=n;G[i]&&e(a,i)}}if(this.scheduleData.cricket){const s=t(this.scheduleData.cricket.events);for(const[n,a]of s){const i=n;G[i]&&e(a,i)}}x.log(`Computed stats for ${this.leagueStats.size} leagues`,"success")}displayAllLeagues(){var s,n,a;if(!this.container)return;const e=this.leagueStats.size,t=Array.from(this.leagueStats.values()).reduce((i,o)=>i+o.totalGames,0);this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            ${this.selectedLeague?'<button class="btn btn-secondary" id="back-to-leagues" style="padding: 0.5rem 1rem; font-size: 0.875rem;">← Back</button>':""}
            <button class="btn btn-primary" id="refresh-leagues" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
            <span class="badge info">${e} Leagues</span>
            <span class="badge success">${t.toLocaleString()} Games</span>
          </div>
        </div>

        <div id="main-content">
          ${this.selectedLeague?this.renderLeagueDetail(this.selectedLeague):this.renderLeagueGrid()}
        </div>
      </div>
    `,(s=this.container.querySelector("#refresh-leagues"))==null||s.addEventListener("click",()=>{$("Refreshing leagues...","success"),this.leagueStats.clear(),this.showLoadingState(),this.loadData()}),this.selectedLeague?((n=this.container.querySelector("#back-to-leagues"))==null||n.addEventListener("click",()=>{this.selectedLeague=null,this.selectedSeason="all",this.selectedTeam="all",this.expandedRaceSessions.clear(),this.displayAllLeagues()}),this.container.querySelectorAll("[data-season]").forEach(i=>{i.addEventListener("click",o=>{this.selectedSeason=o.target.dataset.season||"all",this.displayAllLeagues()})}),this.container.querySelectorAll("[data-team]").forEach(i=>{i.addEventListener("click",o=>{this.selectedTeam=o.target.dataset.team||"all",this.displayAllLeagues()})}),(a=this.container.querySelector("#clear-filters"))==null||a.addEventListener("click",()=>{this.selectedSeason="all",this.selectedTeam="all",this.displayAllLeagues()}),this.container.querySelectorAll("[data-racing-session-id]").forEach(i=>{i.addEventListener("click",()=>{const o=i.dataset.racingSessionId;o&&(this.expandedRaceSessions.has(o)?this.expandedRaceSessions.delete(o):this.expandedRaceSessions.add(o),this.displayAllLeagues())})})):(this.container.querySelectorAll(".filter-btn").forEach(i=>{i.addEventListener("click",o=>{const l=o.target.dataset.sport;l&&(this.currentFilter=l,this.displayAllLeagues())})}),this.container.querySelectorAll("[data-league-id]").forEach(i=>{i.addEventListener("click",()=>{const o=i.dataset.leagueId;o&&(this.selectedLeague=parseInt(o),this.selectedSeason="all",this.selectedTeam="all",this.expandedRaceSessions.clear(),this.displayAllLeagues())})}))}renderLeagueGrid(){return`
      <div style="display: flex; gap: 0.5rem; margin-bottom: 1.5rem; overflow-x: auto; padding: 0.25rem;">
        <button class="filter-btn ${this.currentFilter==="all"?"active":""}" data-sport="all">All Sports</button>
        <button class="filter-btn ${this.currentFilter==="basketball"?"active":""}" data-sport="basketball">Basketball</button>
        <button class="filter-btn ${this.currentFilter==="football"?"active":""}" data-sport="football">Football</button>
        <button class="filter-btn ${this.currentFilter==="hockey"?"active":""}" data-sport="hockey">Hockey</button>
        <button class="filter-btn ${this.currentFilter==="baseball"?"active":""}" data-sport="baseball">Baseball</button>
        <button class="filter-btn ${this.currentFilter==="soccer"?"active":""}" data-sport="soccer">Soccer</button>
        <button class="filter-btn ${this.currentFilter==="golf"?"active":""}" data-sport="golf">Golf</button>
        <button class="filter-btn ${this.currentFilter==="tennis"?"active":""}" data-sport="tennis">Tennis</button>
        <button class="filter-btn ${this.currentFilter==="racing"?"active":""}" data-sport="racing">Racing</button>
        <button class="filter-btn ${this.currentFilter==="cricket"?"active":""}" data-sport="cricket">Cricket</button>
      </div>

      <div id="leagues-container" class="grid grid-2">
        ${this.renderLeagueCards()}
      </div>
    `}renderLeagueCards(){const e=Array.from(this.leagueStats.entries()).filter(([t,s])=>this.currentFilter==="all"?!0:s.sport===this.currentFilter).sort((t,s)=>t[1].liveGames!==s[1].liveGames?s[1].liveGames-t[1].liveGames:t[1].totalGames!==s[1].totalGames?s[1].totalGames-t[1].totalGames:t[1].league.localeCompare(s[1].league));return e.length===0?`<div style="grid-column: 1 / -1; text-align: center; padding: 3rem; color: var(--text-secondary);">
        ${this.currentFilter==="all"?"No schedule data loaded yet":`No ${this.currentFilter} leagues found`}
      </div>`:e.map(([t,s])=>{const n=this.getSportColor(s.sport);return`
        <div class="card league-card" data-league-id="${t}" style="border-left: 4px solid ${n}; cursor: pointer; transition: transform 0.2s, box-shadow 0.2s;">
          <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 1rem;">
            <div>
              <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 0.25rem;">${s.league}</h3>
              <div style="font-size: 0.875rem; color: var(--text-secondary);">${this.capitalizeFirst(s.sport)}</div>
            </div>
            <div style="display: flex; gap: 0.375rem;">
              ${s.liveGames>0?`<span class="badge success">${s.liveGames} Live</span>`:""}
              ${s.totalGames===0?'<span class="badge warning">No data</span>':""}
            </div>
          </div>

          <div class="grid grid-3" style="gap: 1rem;">
            <div style="text-align: center;">
              <div style="font-size: 1.5rem; font-weight: 700; color: var(--primary-color);">${s.totalGames}</div>
              <div style="font-size: 0.75rem; color: var(--text-secondary);">Total</div>
            </div>
            <div style="text-align: center;">
              <div style="font-size: 1.5rem; font-weight: 700; color: var(--success-color);">${s.liveGames}</div>
              <div style="font-size: 0.75rem; color: var(--text-secondary);">Live</div>
            </div>
            <div style="text-align: center;">
              <div style="font-size: 1.5rem; font-weight: 700; color: var(--warning-color);">${s.upcomingGames}</div>
              <div style="font-size: 0.75rem; color: var(--text-secondary);">Upcoming</div>
            </div>
          </div>

          <div style="margin-top: 1rem; text-align: center; font-size: 0.875rem; color: var(--primary-color); font-weight: 500;">
            Click to view games →
          </div>
        </div>
      `}).join("")}getSportForLeague(e){switch(e){case v.NBA:return"basketball";case v.NFL:return"football";case v.NHL:return"hockey";case v.MLB:return"baseball";case v.PGA:return"golf";case v.ATP:case v.WTA:return"tennis";case v.Formula1:case v.NASCARCup:case v.IndyCar:case v.IMSA:case v.WEC:return"racing";default:return xe.has(e)?"cricket":"soccer"}}isIndividualSport(e){return e===v.PGA||e===v.ATP||e===v.WTA||this.isRacingLeague(e)}isIndividualSportGame(e){const t=parseInt(e.idLeague||"0");return t===v.PGA||t===v.ATP||t===v.WTA||this.isRacingLeague(t)}isRacingLeague(e){return[v.Formula1,v.NASCARCup,v.IndyCar,v.IMSA,v.WEC].includes(e)}extractGPName(e){return e.replace(/\s+(Sprint Shootout|Sprint|FP1|FP2|FP3|Qual|Race)$/i,"").trim()}getSessionOrder(e){const t=e.toLowerCase();return t.endsWith(" fp1")?0:t.endsWith(" fp2")?1:t.endsWith(" fp3")?2:t.endsWith(" sprint shootout")?3:t.endsWith(" sprint")?4:t.endsWith(" qual")?5:t.endsWith(" race")?6:7}getSessionLabel(e){const t=e.toLowerCase();return t.endsWith(" fp1")?"Free Practice 1":t.endsWith(" fp2")?"Free Practice 2":t.endsWith(" fp3")?"Free Practice 3":t.endsWith(" sprint shootout")?"Sprint Shootout":t.endsWith(" sprint")?"Sprint":t.endsWith(" qual")?"Qualifying":t.endsWith(" race")?"Race":e}groupRacingGamesByGP(e){const t=new Map;for(const s of e){const n=this.extractGPName(s.strHomeTeam||"");if(!n)continue;const a=t.get(n)||[];a.push(s),t.set(n,a)}for(const[,s]of t)s.sort((n,a)=>this.getSessionOrder(n.strHomeTeam||"")-this.getSessionOrder(a.strHomeTeam||""));return t}getSportColor(e){switch(e){case"basketball":return"#1d428a";case"football":return"#013369";case"hockey":return"#000000";case"baseball":return"#002d72";case"soccer":return"#00a650";case"golf":return"#2ca58d";case"tennis":return"#c8b900";case"racing":return"#e10600";case"cricket":return"#1b7a3e";default:return"var(--primary-color)"}}capitalizeFirst(e){return e.charAt(0).toUpperCase()+e.slice(1)}getGamesForLeague(e){var t;return this.scheduleData?e===v.NBA&&this.scheduleData.nba?this.scheduleData.nba.events:e===v.NFL&&this.scheduleData.nfl?this.scheduleData.nfl.events:e===v.NHL&&this.scheduleData.nhl?this.scheduleData.nhl.events:e===v.MLB&&this.scheduleData.mlb?this.scheduleData.mlb.events:e===v.PGA&&this.scheduleData.golf?this.scheduleData.golf.events:e===v.Formula1&&this.scheduleData.racing?this.scheduleData.racing.events:this.isRacingLeague(e)&&e!==v.Formula1&&this.scheduleData.motorsport?this.scheduleData.motorsport.events.filter(s=>s.idLeague===String(e)):xe.has(e)?(((t=this.scheduleData.cricket)==null?void 0:t.events)??[]).filter(s=>s.idLeague===String(e)):(e===v.ATP||e===v.WTA)&&this.scheduleData.tennis?this.scheduleData.tennis.events.filter(s=>s.idLeague===String(e)):this.scheduleData.soccer?this.scheduleData.soccer.events.filter(s=>s.idLeague===String(e)):[]:[]}renderLeagueDetail(e){const t=this.leagueStats.get(e),s=G[e]||"Unknown League",n=e;if(!t||!this.scheduleData)return'<div style="text-align: center; padding: 3rem; color: var(--text-secondary);">No data available for this league</div>';const a=this.getGamesForLeague(e),i=this.extractSeasons(a),o=this.extractTeams(a),l=this.isIndividualSport(n),c=this.isRacingLeague(e);let d=a;this.selectedSeason!=="all"&&(d=d.filter(y=>this.getGameSeason(y)===this.selectedSeason)),this.selectedTeam!=="all"&&(d=d.filter(y=>c?this.extractGPName(y.strHomeTeam||"")===this.selectedTeam:l?y.strHomeTeam===this.selectedTeam:y.strHomeTeam===this.selectedTeam||y.strAwayTeam===this.selectedTeam));const m=["ft","aot","final","final/ot","post","ap","completed","finished","match finished"],g=["ns","pre","","scheduled","not started"],p=d.filter(y=>{const M=(y.strStatus||"").toLowerCase();return!m.includes(M)&&!g.includes(M)}),h=d.filter(y=>{const M=(y.strStatus||"").toLowerCase();return g.includes(M)}).sort((y,M)=>{const W=new Date(y.isoDate||y.strTimestamp||0).getTime(),K=new Date(M.isoDate||M.strTimestamp||0).getTime();return W-K}),u=d.filter(y=>{const M=(y.strStatus||"").toLowerCase();return m.includes(M)}).sort((y,M)=>{const W=new Date(y.isoDate||y.strTimestamp||0).getTime();return new Date(M.isoDate||M.strTimestamp||0).getTime()-W}),b=this.getSportForLeague(n),E=this.getSportColor(b),A=this.selectedSeason!=="all"||this.selectedTeam!=="all",S=c?this.groupRacingGamesByGP(p):null,P=c?this.groupRacingGamesByGP(h):null,L=c?this.groupRacingGamesByGP(u):null,F=c?"Grand Prix":l?"Tournament":"Team",I=c?"Grand Prix":l?"Tournaments":"Teams",Y=c?"sessions":l?"events":"games";return`
      <div style="border-left: 4px solid ${E}; padding-left: 1rem; margin-bottom: 1.5rem;">
        <h2 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 0.25rem;">${s}</h2>
        <div style="color: var(--text-secondary); font-size: 0.875rem;">${this.capitalizeFirst(b)} &middot; ${a.length} total ${Y} &middot; ${t.teams.length} ${I}</div>
      </div>

      <!-- Filter Controls -->
      <div style="margin-bottom: 1.5rem;">
        ${i.length>1?`
          <div style="margin-bottom: 1rem;">
            <label style="display: block; font-size: 0.875rem; font-weight: 600; margin-bottom: 0.5rem;">Season</label>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <button class="filter-btn ${this.selectedSeason==="all"?"active":""}" data-season="all">All Seasons</button>
              ${i.map(y=>`
                <button class="filter-btn ${this.selectedSeason===y?"active":""}" data-season="${y}">${y}</button>
              `).join("")}
            </div>
          </div>
        `:""}

        ${o.length>1&&o.length<=40?`
          <div>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
              <label style="font-size: 0.875rem; font-weight: 600;">${F}</label>
              ${A?'<button class="btn btn-secondary" id="clear-filters" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear Filters</button>':""}
            </div>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <button class="filter-btn ${this.selectedTeam==="all"?"active":""}" data-team="all">All ${I}</button>
              ${o.map(y=>`
                <button class="filter-btn ${this.selectedTeam===y?"active":""}" data-team="${y}">${y}</button>
              `).join("")}
            </div>
          </div>
        `:A?'<button class="btn btn-secondary" id="clear-filters" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear Filters</button>':""}
      </div>

      <div class="grid grid-3" style="margin-bottom: 1.5rem;">
        <div class="stat-card">
          <div class="stat-value">${d.length}</div>
          <div class="stat-label">Games${A?" (Filtered)":""}</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" style="color: var(--success-color);">${p.length}</div>
          <div class="stat-label">Live</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" style="color: var(--warning-color);">${h.length}</div>
          <div class="stat-label">Upcoming</div>
        </div>
      </div>

      ${p.length>0?`
        <div class="card" style="margin-bottom: 1.5rem; border-left: 4px solid var(--success-color);">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem; display: flex; align-items: center; gap: 0.5rem;">
            <span class="badge success">Live</span>
            ${c&&S?`${S.size} Grand Prix In Progress (${p.length} sessions)`:`${p.length} Games In Progress`}
          </h3>
          <div style="display: grid; gap: 1rem;">
            ${c&&S?Array.from(S.entries()).map(([y,M])=>this.renderRacingGPGroup(y,M,"live")).join(""):p.map(y=>l?this.renderTournamentCard(y):this.renderGameCard(y)).join("")}
          </div>
        </div>
      `:""}

      ${h.length>0?`
        <div class="card" style="margin-bottom: 1.5rem;">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
            ${c&&P?`Upcoming Grand Prix (${P.size} GPs, ${h.length} sessions)`:`Upcoming ${l?"Events":"Games"} (${h.length})`}
          </h3>
          ${c&&P?`
            <div>
              ${Array.from(P.entries()).map(([y,M])=>this.renderRacingGPGroup(y,M,"upcoming")).join("")}
            </div>
          `:`
            <table>
              <thead>
                <tr>
                  ${l?`
                    <th>Tournament</th>
                    <th>Status</th>
                    <th>Time</th>
                  `:`
                    <th>Home Team</th>
                    <th>Away Team</th>
                    <th>Status</th>
                    <th>Time</th>
                  `}
                </tr>
              </thead>
              <tbody>
                ${h.slice(0,25).map(y=>l?this.renderTournamentRow(y):this.renderGameRow(y)).join("")}
              </tbody>
            </table>
            ${h.length>25?`<div style="text-align: center; margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">Showing 25 of ${h.length} upcoming ${l?"events":"games"}</div>`:""}
          `}
        </div>
      `:""}

      ${u.length>0?`
        <div class="card">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
            ${c&&L?`Completed Grand Prix (${L.size} GPs, ${u.length} sessions)`:`Completed ${l?"Events":"Games"} (${u.length})`}
          </h3>
          ${c&&L?`
            <div>
              ${Array.from(L.entries()).map(([y,M])=>this.renderRacingGPGroup(y,M,"completed")).join("")}
            </div>
          `:`
            <table>
              <thead>
                <tr>
                  ${l?`
                    <th>Tournament</th>
                    <th>Leader</th>
                    <th>Score</th>
                    <th>Status</th>
                  `:`
                    <th>Home Team</th>
                    <th>Away Team</th>
                    <th>Score</th>
                    <th>Status</th>
                  `}
                </tr>
              </thead>
              <tbody>
                ${u.slice(0,25).map(y=>l?this.renderTournamentRow(y):this.renderGameRow(y)).join("")}
              </tbody>
            </table>
            ${u.length>25?`<div style="text-align: center; margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">Showing 25 of ${u.length} completed ${l?"events":"games"}</div>`:""}
          `}
        </div>
      `:""}

      ${d.length===0?'<div style="text-align: center; padding: 3rem; color: var(--text-secondary);">No games found for this league</div>':""}
    `}renderGameCard(e){const t=O(e.strStatus),s=e.intHomeScore||"0",n=e.intAwayScore||"0";return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem; background-color: var(--surface-color);">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem;">
          <span class="${t.class}">${t.text}</span>
          <span style="font-size: 0.875rem; color: var(--text-secondary);">${e.strProgress||""}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${e.strHomeTeamBadge?`<img src="${e.strHomeTeamBadge}" alt="${e.strHomeTeam}" style="width: 32px; height: 32px; object-fit: contain;">`:""}
            <span style="font-weight: 600;">${e.strHomeTeam}</span>
          </div>
          <span style="font-size: 1.75rem; font-weight: 700; min-width: 60px; text-align: center;">${s}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${e.strAwayTeamBadge?`<img src="${e.strAwayTeamBadge}" alt="${e.strAwayTeam}" style="width: 32px; height: 32px; object-fit: contain;">`:""}
            <span style="font-weight: 600;">${e.strAwayTeam}</span>
          </div>
          <span style="font-size: 1.75rem; font-weight: 700; min-width: 60px; text-align: center;">${n}</span>
        </div>
      </div>
    `}renderTournamentCard(e){const t=O(e.strStatus),s=(e.lastPlay||"").split(`
`).filter(a=>a.includes("|")).map((a,i)=>{const[o,l]=a.split("|");return{position:i+1,name:o||"TBD",score:l||"--"}}),n=s.length>0?s.map(a=>`
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0; ${a.position===1?"font-weight: 600;":"color: var(--text-secondary);"}">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${a.position}</span>
              <span>${a.name}</span>
            </div>
            <span style="font-weight: 500;">${a.score}</span>
          </div>
        `).join(""):e.strAwayTeam&&e.strAwayTeam!=="TBD"?`<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0;">
              <span>${e.strAwayTeam}</span>
              <span style="font-weight: 600;">${e.intAwayScore||"--"}</span>
           </div>`:"";return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem; background-color: var(--surface-color);">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span style="font-weight: 600; font-size: 1.1rem;">${e.strHomeTeam}</span>
          <span class="${t.class}">${t.text}</span>
        </div>
        ${e.strProgress?`<div style="font-size: 0.8rem; color: var(--text-secondary); margin-bottom: 0.5rem;">${e.strProgress}</div>`:""}
        ${n?`<div style="border-top: 1px solid var(--border-color); padding-top: 0.5rem;">${n}</div>`:""}
      </div>
    `}renderGameRow(e){const t=O(e.strStatus),s=e.intHomeScore||"-",n=e.intAwayScore||"-";return`
      <tr>
        <td>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            ${e.strHomeTeamBadge?`<img src="${e.strHomeTeamBadge}" alt="${e.strHomeTeam}" style="width: 20px; height: 20px; object-fit: contain;">`:""}
            <span>${e.strHomeTeam}</span>
          </div>
        </td>
        <td>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            ${e.strAwayTeamBadge?`<img src="${e.strAwayTeamBadge}" alt="${e.strAwayTeam}" style="width: 20px; height: 20px; object-fit: contain;">`:""}
            <span>${e.strAwayTeam}</span>
          </div>
        </td>
        <td>${s} - ${n}</td>
        <td><span class="${t.class}">${t.text}</span></td>
        <td style="font-size: 0.875rem;">${e.strProgress||V(e.strTimestamp)}</td>
      </tr>
    `}renderTournamentRow(e){const t=O(e.strStatus),s=e.strAwayTeam!=="TBD"?e.strAwayTeam:"",n=e.intAwayScore||"-";return`
      <tr>
        <td>
          <span style="font-weight: 500;">${e.strHomeTeam}</span>
        </td>
        ${s?`<td>${s}</td><td>${n}</td>`:'<td colspan="2" style="color: var(--text-secondary);">-</td>'}
        <td><span class="${t.class}">${t.text}</span></td>
        <td style="font-size: 0.875rem;">${e.strProgress||V(e.strTimestamp)}</td>
      </tr>
    `}renderRacingLeaderboard(e){const t=(e.lastPlay||"").split(`
`).filter(n=>n.includes("|"));return t.length===0?'<div style="padding: 0.5rem; color: var(--text-secondary); font-size: 0.8rem;">No leaderboard data</div>':`
      <table style="width: 100%; font-size: 0.8rem; margin-top: 0.5rem; border-collapse: collapse;">
        <thead>
          <tr style="border-bottom: 1px solid var(--border-color);">
            <th style="text-align: left; padding: 0.25rem 0.5rem; font-weight: 600; width: 2rem;">Pos</th>
            <th style="text-align: left; padding: 0.25rem 0.5rem; font-weight: 600;">Driver</th>
            <th style="text-align: left; padding: 0.25rem 0.5rem; font-weight: 600;">Constructor</th>
            <th style="text-align: right; padding: 0.25rem 0.5rem; font-weight: 600;">Score</th>
            <th style="text-align: right; padding: 0.25rem 0.5rem; font-weight: 600;">Gap</th>
          </tr>
        </thead>
        <tbody>
          ${t.map((n,a)=>{const i=n.split("|");return{position:a+1,name:i[0]||"",score:i[1]||"",gap:i[2]||"",constructor:i[3]||""}}).map(n=>`
            <tr style="${n.position===1?"font-weight: 600;":"color: var(--text-secondary);"} ${n.position<=3?"background-color: rgba(225, 6, 0, 0.03);":""}">
              <td style="padding: 0.2rem 0.5rem;">${n.position}</td>
              <td style="padding: 0.2rem 0.5rem;">${n.name}</td>
              <td style="padding: 0.2rem 0.5rem; font-size: 0.75rem;">${n.constructor||"-"}</td>
              <td style="text-align: right; padding: 0.2rem 0.5rem;">${n.score||"-"}</td>
              <td style="text-align: right; padding: 0.2rem 0.5rem;">${n.gap||"-"}</td>
            </tr>
          `).join("")}
        </tbody>
      </table>
    `}renderRacingGPGroup(e,t,s){const n=t.find(c=>(c.strHomeTeam||"").toLowerCase().endsWith(" race")),a=t[0],i=a?V(a.strTimestamp):"";let o="",l="";if(s==="completed"&&n){const c=(n.lastPlay||"").split(`
`).filter(d=>d.includes("|"));if(c.length>0){const d=c[0].split("|");o=d[0]||"",l=d[3]||""}else n.strAwayTeam&&n.strAwayTeam!=="TBD"&&(o=n.strAwayTeam)}return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.5rem; margin-bottom: 0.75rem; overflow: hidden;">
        <div style="padding: 0.75rem 1rem; background: linear-gradient(135deg, rgba(225, 6, 0, 0.05), transparent); border-bottom: 1px solid var(--border-color);">
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <div>
              <div style="font-weight: 700; font-size: 1rem;">${e}</div>
              ${o?`<div style="font-size: 0.8rem; color: var(--text-secondary); margin-top: 0.125rem;">Winner: <span style="font-weight: 600; color: var(--text-primary);">${o}</span>${l?` <span style="font-size: 0.75rem; color: var(--text-secondary);">(${l})</span>`:""}</div>`:""}
            </div>
            <div style="display: flex; gap: 0.5rem; align-items: center;">
              <span style="font-size: 0.75rem; color: var(--text-secondary);">${i}</span>
              <span class="badge info" style="font-size: 0.7rem;">${t.length} sessions</span>
            </div>
          </div>
        </div>
        <div style="padding: 0;">
          ${t.map(c=>this.renderRacingSessionRow(c,s)).join("")}
        </div>
      </div>
    `}renderRacingSessionRow(e,t){const s=this.getSessionLabel(e.strHomeTeam||""),n=O(e.strStatus),a=(e.strHomeTeam||"").toLowerCase().endsWith(" race"),i=this.expandedRaceSessions.has(e.idEvent||""),l=t==="completed"&&(e.lastPlay||"").includes("|");let c="",d="",m="";if(t==="completed"){const p=(e.lastPlay||"").split(`
`).filter(h=>h.includes("|"));if(p.length>0){const h=p[0].split("|");c=h[0]||"",m=h[1]||"",d=h[3]||""}else e.strAwayTeam&&e.strAwayTeam!=="TBD"&&(c=e.strAwayTeam)}const g=a?"rgba(225, 6, 0, 0.04)":"transparent";return`
      <div ${l?`data-racing-session-id="${e.idEvent}"`:""} style="padding: 0.5rem 1rem; border-bottom: 1px solid var(--border-color); background-color: ${g}; ${l?"cursor: pointer;":""} display: flex; flex-direction: column; transition: background-color 0.15s;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            ${l?`<span style="font-size: 0.7rem; color: var(--text-secondary); transition: transform 0.2s; transform: rotate(${i?"90":"0"}deg); display: inline-block;">&#9654;</span>`:'<span style="width: 0.7rem; display: inline-block;"></span>'}
            <span style="font-weight: ${a?"600":"500"}; font-size: 0.875rem;">${s}</span>
            ${c&&!i?`<span style="font-size: 0.8rem; color: var(--text-secondary);">${c}${d?` <span style="font-size: 0.75rem;">(${d})</span>`:""}${m?` <span style="font-size: 0.75rem; color: var(--text-secondary);">P${m}</span>`:""}</span>`:""}
          </div>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <span style="font-size: 0.8rem; color: var(--text-secondary);">${e.strProgress||V(e.strTimestamp)}</span>
            <span class="${n.class}" style="font-size: 0.7rem;">${n.text}</span>
          </div>
        </div>
        ${i?`<div style="padding: 0.5rem 0 0.25rem 2rem;">${this.renderRacingLeaderboard(e)}</div>`:""}
      </div>
    `}extractSeasons(e){const t=new Set;for(const s of e){const n=this.getGameSeason(s);n&&t.add(n)}return Array.from(t).sort().reverse()}extractTeams(e){var a;const t=new Set,s=parseInt(((a=e[0])==null?void 0:a.idLeague)||"0"),n=this.isRacingLeague(s);for(const i of e)if(n){const o=this.extractGPName(i.strHomeTeam||"");o&&t.add(o)}else this.isIndividualSportGame(i)?i.strHomeTeam&&i.strHomeTeam!=="TBD"&&t.add(i.strHomeTeam):(i.strHomeTeam&&t.add(i.strHomeTeam),i.strAwayTeam&&t.add(i.strAwayTeam));return Array.from(t).sort()}getGameSeason(e){const t=e.strTimestamp||e.isoDate;if(!t)return null;try{const s=new Date(t),n=s.getFullYear();return s.getMonth()+1>=8?`${n}-${n+1}`:`${n-1}-${n}`}catch{return null}}}class ls{constructor(){f(this,"container",null)}async render(e){this.container=e,this.container.innerHTML='<div class="loading">Analyzing data gaps...</div>';try{const t=await _.getDataGaps();this.displayGaps(t)}catch(t){console.error("Failed to fetch data gaps:",t),$("Failed to analyze data gaps","error")}}stop(){}displayGaps(e){this.container&&(this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Data Completeness Analysis</h2>
          <span class="badge ${e.summary.overallCompleteness>.95?"success":e.summary.overallCompleteness>.8?"warning":"danger"}">
            ${$e(e.summary.overallCompleteness)} Complete
          </span>
        </div>

        <div class="grid grid-3">
          <div class="stat-card">
            <div class="stat-value">${e.summary.totalLeagues}</div>
            <div class="stat-label">Total Leagues</div>
          </div>
          <div class="stat-card">
            <div class="stat-value">${e.summary.totalGames}</div>
            <div class="stat-label">Total Games</div>
          </div>
          <div class="stat-card">
            <div class="stat-value">${e.summary.leaguesWithIssues}</div>
            <div class="stat-label">Leagues with Issues</div>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Details</h2>
        </div>
        <table>
          <thead>
            <tr>
              <th>League</th>
              <th>Sport</th>
              <th>Total Games</th>
              <th>Missing Badges</th>
              <th>Missing Scores</th>
              <th>Missing Timestamps</th>
              <th>Completeness</th>
            </tr>
          </thead>
          <tbody>
            ${e.leagues.sort((t,s)=>t.completeness-s.completeness).map(t=>this.renderLeagueRow(t)).join("")}
          </tbody>
        </table>
      </div>

      ${this.renderRecommendations(e)}
    `)}renderLeagueRow(e){const t=e.completeness,s=t>.95?"success":t>.8?"warning":"danger";return`
      <tr>
        <td style="font-weight: 500;">${e.league}</td>
        <td>${e.sport}</td>
        <td>${e.totalGames}</td>
        <td ${e.gamesWithoutBadges>0?'style="color: var(--danger-color); font-weight: 600;"':""}>${e.gamesWithoutBadges}</td>
        <td ${e.gamesWithoutScores>0?'style="color: var(--warning-color); font-weight: 600;"':""}>${e.gamesWithoutScores}</td>
        <td ${e.gamesWithoutTimestamps>0?'style="color: var(--danger-color); font-weight: 600;"':""}>${e.gamesWithoutTimestamps}</td>
        <td><span class="badge ${s}">${$e(t)}</span></td>
      </tr>
    `}renderRecommendations(e){const t=e.leagues.filter(s=>s.completeness<1);return t.length===0?`
        <div class="card">
          <div style="text-align: center; padding: 2rem; color: var(--success-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">✓</div>
            <div style="font-weight: 600; font-size: 1.125rem;">All data looks good!</div>
            <div style="color: var(--text-secondary); margin-top: 0.5rem;">No data gaps detected.</div>
          </div>
        </div>
      `:`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Recommendations</h2>
        </div>
        <ul style="list-style: none; padding: 0;">
          ${t.map(s=>{const n=[];return s.gamesWithoutBadges>0&&n.push(`Missing ${s.gamesWithoutBadges} team badges`),s.gamesWithoutScores>0&&n.push(`Missing ${s.gamesWithoutScores} scores`),s.gamesWithoutTimestamps>0&&n.push(`Missing ${s.gamesWithoutTimestamps} timestamps`),`
              <li style="padding: 0.75rem 0; border-bottom: 1px solid var(--border-color);">
                <div style="font-weight: 600; margin-bottom: 0.25rem;">${s.league}</div>
                <div style="font-size: 0.875rem; color: var(--text-secondary);">
                  ${n.join(" • ")}
                </div>
              </li>
            `}).join("")}
        </ul>
      </div>
    `}}class cs{constructor(){f(this,"container",null);f(this,"keys",[]);f(this,"filteredKeys",[])}async render(e){this.container=e,x.log("Redis Viewer initialized","info"),this.container.innerHTML='<div class="loading">Loading Redis keys...</div>',await this.loadKeys()}async loadKeys(){var t;x.log("Fetching Redis keys from /api/admin/redis/keys...","info");const e=Date.now();try{const s=await _.getRedisKeys(),n=Date.now()-e;x.log(`Loaded ${s.keys.length} Redis keys in ${n}ms`,"success"),this.keys=s.keys,this.filteredKeys=this.keys,this.displayKeys()}catch(s){const n=Date.now()-e;x.log(`Failed to fetch Redis keys after ${n}ms: ${s}`,"error"),console.error("Failed to fetch Redis keys:",s),$("Failed to fetch Redis keys","error"),this.container&&(this.container.innerHTML=`
          <div class="card">
            <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
              <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
              <div style="font-weight: 600; font-size: 1.125rem;">Failed to load Redis keys</div>
              <button class="btn btn-primary" id="retry-redis" style="margin-top: 1rem;">🔄 Retry</button>
            </div>
          </div>
        `,(t=this.container.querySelector("#retry-redis"))==null||t.addEventListener("click",()=>this.loadKeys()))}}stop(){}displayKeys(){if(!this.container)return;this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Redis Keys</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-primary" id="refresh-redis" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
            <span class="badge info">${this.keys.length} Keys</span>
          </div>
        </div>

        <div style="margin-bottom: 1rem;">
          <input
            type="text"
            id="key-search"
            class="input"
            placeholder="Search keys..."
          />
        </div>

        <div style="max-height: 600px; overflow-y: auto;">
          <table id="keys-table">
            <thead>
              <tr>
                <th>Key</th>
                <th>Type</th>
                <th>Size</th>
                <th>TTL</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody id="keys-table-body">
              ${this.filteredKeys.map((s,n)=>this.renderKeyRow(s,n)).join("")}
            </tbody>
          </table>
        </div>
      </div>

      <div id="key-detail" style="display: none;"></div>
    `;const e=this.container.querySelector("#refresh-redis");e==null||e.addEventListener("click",()=>{x.log("Manual refresh triggered","info"),$("Refreshing Redis keys...","success"),this.loadKeys()}),this.container.querySelector("#key-search").addEventListener("input",s=>{const n=s.target.value.toLowerCase();this.filteredKeys=this.keys.filter(a=>a.key.toLowerCase().includes(n)),this.updateKeysTable()}),this.setupActionListeners()}renderKeyRow(e,t){return`
      <tr>
        <td style="font-family: monospace; font-size: 0.875rem;">${this.escapeHtml(e.key)}</td>
        <td><span class="badge info">${e.type}</span></td>
        <td>${be(e.size)}</td>
        <td>${we(e.ttl)}</td>
        <td style="white-space: nowrap;">
          <button class="btn btn-secondary btn-view" data-index="${t}" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; min-width: 70px;">View</button>
          <button class="btn btn-danger btn-delete" data-index="${t}" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; margin-left: 0.25rem;">Delete</button>
        </td>
      </tr>
    `}escapeHtml(e){const t=document.createElement("div");return t.textContent=e,t.innerHTML}updateKeysTable(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#keys-table-body");e&&(e.innerHTML=this.filteredKeys.map((s,n)=>this.renderKeyRow(s,n)).join(""))}setupActionListeners(){var s;const e=(s=this.container)==null?void 0:s.querySelector("#keys-table");if(!e){x.log("Keys table not found, cannot setup listeners","error");return}const t=n=>{const a=n.target;if(a.classList.contains("btn-view")){n.preventDefault(),n.stopPropagation();const i=parseInt(a.dataset.index||"-1");if(x.log(`View button clicked, index: ${i}, filteredKeys length: ${this.filteredKeys.length}`,"info"),i>=0&&i<this.filteredKeys.length){const o=this.filteredKeys[i].key;x.log(`Viewing key: ${o}`,"info");const l=a;l.disabled=!0,l.textContent="Loading...",this.viewKey(o).finally(()=>{l.disabled=!1,l.textContent="View"})}else x.log(`Invalid index: ${i}`,"error")}else if(a.classList.contains("btn-delete")){n.preventDefault(),n.stopPropagation();const i=parseInt(a.dataset.index||"-1");if(i>=0&&i<this.filteredKeys.length){const o=this.filteredKeys[i].key;this.deleteKey(o)}}};e.addEventListener("click",t),x.log(`Event delegation set up for ${this.filteredKeys.length} keys`,"info")}async viewKey(e){var s,n,a,i;x.log(`Viewing Redis key: ${e}`,"info");const t=(s=this.container)==null?void 0:s.querySelector("#key-detail");if(!t){x.log("Detail div not found","error");return}t.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h3 class="card-title" style="font-family: monospace; font-size: 1rem; word-break: break-all;">${this.escapeHtml(e)}</h3>
        </div>
        <div style="text-align: center; padding: 3rem;">
          <div class="loading">Loading key value...</div>
        </div>
      </div>
    `,t.style.display="block";try{const o=Date.now(),l=await _.getRedisKey(e),c=Date.now()-o;x.log(`Key content loaded (${l.value.length} bytes) in ${c}ms`,"success");const d=ts(l.value);t.innerHTML=`
        <div class="card">
          <div class="card-header">
            <h3 class="card-title" style="font-family: monospace; font-size: 1rem; word-break: break-all;">${this.escapeHtml(e)}</h3>
            <div style="display: flex; gap: 0.5rem;">
              <span class="badge info">${l.type}</span>
              ${l.ttl?`<span class="badge warning">TTL: ${we(l.ttl)}</span>`:""}
              <span class="badge info">${be(l.value.length)}</span>
            </div>
          </div>
          <div class="json-viewer"><pre style="margin: 0;">${d}</pre></div>
          <div style="margin-top: 1rem; display: flex; gap: 0.5rem;">
            <button class="btn btn-secondary" id="copy-json">📋 Copy</button>
            <button class="btn btn-danger" id="close-detail">Close</button>
          </div>
        </div>
      `,(n=t.querySelector("#copy-json"))==null||n.addEventListener("click",()=>{navigator.clipboard.writeText(l.value),$("Copied to clipboard","success")}),(a=t.querySelector("#close-detail"))==null||a.addEventListener("click",()=>{t&&(t.style.display="none")}),this.setupJSONCollapseHandlers(t),t.scrollIntoView({behavior:"smooth",block:"nearest"})}catch(o){x.log(`Failed to fetch key content: ${o}`,"error"),console.error("Failed to fetch key content:",o),$("Failed to fetch key content","error"),t.innerHTML=`
        <div class="card">
          <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
            <div style="font-weight: 600; font-size: 1.125rem;">Failed to load key</div>
            <div style="margin-top: 0.5rem; font-size: 0.875rem; color: var(--text-secondary);">${o}</div>
            <button class="btn btn-danger" id="close-error" style="margin-top: 1rem;">Close</button>
          </div>
        </div>
      `,(i=t.querySelector("#close-error"))==null||i.addEventListener("click",()=>{t&&(t.style.display="none")})}}async deleteKey(e){if(confirm(`Are you sure you want to delete key "${e}"?`))try{const t=await _.invalidateKey(e);$(t.message,t.success?"success":"warning"),t.success&&(this.keys=this.keys.filter(s=>s.key!==e),this.filteredKeys=this.filteredKeys.filter(s=>s.key!==e),this.updateKeysTable())}catch(t){console.error("Failed to delete key:",t),$("Failed to delete key","error")}}setupJSONCollapseHandlers(e){const t=e.querySelectorAll(".json-collapse-btn");t.forEach(s=>{s.addEventListener("click",n=>{n.preventDefault();const a=n.target,i=a.dataset.target;if(i){const o=e.querySelector(`#${i}`);if(o){const l=o.classList.toggle("collapsed");a.classList.toggle("collapsed");const c=a.textContent||"";l?a.textContent=c.replace("▼","▶"):a.textContent=c.replace("▶","▼")}}})}),x.log(`Set up ${t.length} JSON collapse handlers`,"info")}}class ds{constructor(){f(this,"container",null);f(this,"teams",[]);f(this,"filteredTeams",[])}async render(e){this.container=e,this.container.innerHTML='<div class="loading">Loading teams...</div>';try{this.teams=await _.getTeams(),this.filteredTeams=this.teams,this.displayTeams()}catch(t){console.error("Failed to fetch teams:",t),$("Failed to fetch teams","error")}}stop(){}displayTeams(){if(!this.container)return;const e=this.teams.filter(s=>!s.strTeamBadge).length;this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Teams</h2>
          <div style="display: flex; gap: 0.5rem;">
            <span class="badge info">${this.teams.length} Total</span>
            ${e>0?`<span class="badge warning">${e} Missing Badges</span>`:""}
          </div>
        </div>

        <div style="margin-bottom: 1rem;">
          <input
            type="text"
            id="team-search"
            class="input"
            placeholder="Search teams..."
          />
        </div>

        <div id="teams-grid" class="grid grid-3">
          ${this.filteredTeams.map(s=>this.renderTeamCard(s)).join("")}
        </div>
      </div>
    `,this.container.querySelector("#team-search").addEventListener("input",s=>{const n=s.target.value.toLowerCase();this.filteredTeams=this.teams.filter(a=>{var i,o,l;return((i=a.strTeam)==null?void 0:i.toLowerCase().includes(n))||((o=a.strTeamShort)==null?void 0:o.toLowerCase().includes(n))||((l=a.strAlternate)==null?void 0:l.toLowerCase().includes(n))}),this.updateTeamsGrid()})}renderTeamCard(e){return`
      <div class="card" style="text-align: center; padding: 1rem;">
        ${e.strTeamBadge?`<img src="${e.strTeamBadge}" alt="${e.strTeam}" style="width: 64px; height: 64px; margin: 0 auto 0.5rem; object-fit: contain;">`:'<div style="width: 64px; height: 64px; margin: 0 auto 0.5rem; background-color: var(--border-color); border-radius: 0.375rem; display: flex; align-items: center; justify-content: center; color: var(--text-secondary);">No Logo</div>'}
        <div style="font-weight: 600; margin-bottom: 0.25rem;">${e.strTeam||"Unknown"}</div>
        ${e.strTeamShort?`<div style="font-size: 0.875rem; color: var(--text-secondary);">${e.strTeamShort}</div>`:""}
        ${e.idTeam?`<div style="font-size: 0.75rem; color: var(--text-secondary); margin-top: 0.25rem;">ID: ${e.idTeam}</div>`:""}
      </div>
    `}updateTeamsGrid(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#teams-grid");e&&(e.innerHTML=this.filteredTeams.map(s=>this.renderTeamCard(s)).join(""))}}class hs{constructor(){f(this,"container",null);f(this,"intervalId",null)}render(e){var t,s,n,a;this.container=e,this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Push-to-Start Registrations</h2>
          <button class="btn btn-primary" id="refresh-registrations" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="registrations-content" class="loading">Loading registrations...</div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Pipeline Status</h2>
          <button class="btn btn-primary" id="refresh-pipeline" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="pipeline-content" class="loading">Loading diagnostics...</div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Trigger Push-to-Start</h2>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Send a push-to-start Live Activity notification to registered devices.
          Select an event ID from the registrations above, or type one manually.
        </p>

        <div style="display: flex; flex-direction: column; gap: 0.75rem; max-width: 500px;">
          <div>
            <label style="display: block; font-weight: 600; margin-bottom: 0.25rem; font-size: 0.875rem;">Event ID</label>
            <input type="text" id="debug-event-id" placeholder="debug-fake-XXXXXXXX"
              style="width: 100%; padding: 0.5rem; border: 1px solid var(--border-color); border-radius: 0.375rem; background: var(--bg-color); color: var(--text-color); font-family: monospace;" />
          </div>
          <div style="display: flex; gap: 0.75rem;">
            <div style="flex: 1;">
              <label style="display: block; font-weight: 600; margin-bottom: 0.25rem; font-size: 0.875rem;">Home Team</label>
              <input type="text" id="debug-home-team" value="Debug Lions"
                style="width: 100%; padding: 0.5rem; border: 1px solid var(--border-color); border-radius: 0.375rem; background: var(--bg-color); color: var(--text-color);" />
            </div>
            <div style="flex: 1;">
              <label style="display: block; font-weight: 600; margin-bottom: 0.25rem; font-size: 0.875rem;">Away Team</label>
              <input type="text" id="debug-away-team" value="Debug Tigers"
                style="width: 100%; padding: 0.5rem; border: 1px solid var(--border-color); border-radius: 0.375rem; background: var(--bg-color); color: var(--text-color);" />
            </div>
          </div>
          <div style="display: flex; gap: 0.75rem; align-self: flex-start;">
            <button class="btn btn-primary" id="trigger-push-to-start">
              Send Push-to-Start
            </button>
            <button class="btn btn-primary" id="trigger-all-push-to-start" style="background: var(--success-color, #22c55e);">
              Start All Debug Games
            </button>
          </div>
        </div>

        <div id="debug-result" style="margin-top: 1rem;"></div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">How to Test</h2>
        </div>
        <ol style="color: var(--text-secondary); line-height: 1.8; padding-left: 1.25rem;">
          <li>On the iOS app: <strong>Settings → Developer → Live Activity Testing</strong></li>
          <li>Create a fake upcoming game → tap its menu → <strong>Auto-Follow</strong></li>
          <li>Wait for the registration to appear above (refresh if needed)</li>
          <li><strong>Force-quit the iOS app</strong></li>
          <li>Click the event ID above to select it, then tap <strong>Send Push-to-Start</strong></li>
          <li>A Live Activity should appear on the device lock screen</li>
        </ol>
      </div>
    `,(t=this.container.querySelector("#refresh-registrations"))==null||t.addEventListener("click",()=>this.fetchRegistrations()),(s=this.container.querySelector("#refresh-pipeline"))==null||s.addEventListener("click",()=>this.fetchDiagnostics()),(n=this.container.querySelector("#trigger-push-to-start"))==null||n.addEventListener("click",()=>{this.triggerPushToStart(this.container.querySelector("#trigger-push-to-start"))}),(a=this.container.querySelector("#trigger-all-push-to-start"))==null||a.addEventListener("click",()=>{this.triggerAllPushToStart(this.container.querySelector("#trigger-all-push-to-start"))}),this.fetchRegistrations(),this.fetchDiagnostics(),this.intervalId=setInterval(()=>{this.fetchRegistrations(),this.fetchDiagnostics()},1e4)}stop(){this.intervalId&&(clearInterval(this.intervalId),this.intervalId=null)}async fetchDiagnostics(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#pipeline-content");if(e)try{const s=await _.getPushToStartDiagnostics();let n=`
        <div style="display: flex; gap: 0.75rem; flex-wrap: wrap; margin-bottom: 1rem;">
          ${s.system.map(a=>`
            <span class="badge ${a.ok?"success":"danger"}" style="padding: 0.375rem 0.75rem; font-size: 0.8rem;">
              ${a.ok?"✅":"❌"} ${a.name}: ${a.detail}
            </span>
          `).join("")}
        </div>
      `;if(s.tokens.length===0)n+='<div style="color: var(--text-secondary); font-size: 0.875rem;">No tokens registered — pipeline steps will appear here once a device registers.</div>';else for(const a of s.tokens)n+=`
            <div style="margin-bottom: 1rem; padding: 0.75rem; border: 1px solid var(--border-color); border-radius: 0.375rem;">
              <div style="font-weight: 600; margin-bottom: 0.5rem; font-family: monospace; font-size: 0.8rem;">${a.tokenPrefix}</div>
              <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
                ${a.steps.map(i=>{const o={green:"#22c55e",yellow:"#eab308",red:"#ef4444"},l={green:"rgba(34,197,94,0.1)",yellow:"rgba(234,179,8,0.1)",red:"rgba(239,68,68,0.1)"};return`<span style="display: inline-flex; align-items: center; gap: 0.25rem; padding: 0.25rem 0.5rem; border-radius: 0.25rem; font-size: 0.75rem; background: ${l[i.status]||l.red}; color: ${o[i.status]||o.red}; border: 1px solid ${o[i.status]||o.red}30;">
                    <span style="width: 8px; height: 8px; border-radius: 50%; background: ${o[i.status]||o.red};"></span>
                    ${i.name}
                    <span style="opacity: 0.7; font-size: 0.7rem;">(${i.detail})</span>
                  </span>`}).join("")}
              </div>
            </div>
          `;e.innerHTML=n}catch(s){const n=s instanceof Error?s.message:"Unknown error";e.innerHTML=`
        <div style="color: var(--danger-color); font-size: 0.875rem;">
          Failed to load diagnostics: ${n}
        </div>
      `}}async fetchRegistrations(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#registrations-content");if(e)try{const s=await _.getPushToStartRegistrations();if(s.totalTokens===0){e.innerHTML=`
          <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
            <div style="font-size: 2rem; margin-bottom: 0.5rem;">📭</div>
            <div>No push-to-start registrations found.</div>
            <div style="font-size: 0.875rem; margin-top: 0.25rem;">Create a fake game and auto-follow it in the iOS app first.</div>
          </div>
        `;return}let n=`
        <div style="font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 0.75rem;">
          ${s.totalTokens} registered device(s). Click an event ID to select it for triggering.
        </div>
        <table>
          <thead>
            <tr>
              <th>Token</th>
              <th>Favorites</th>
              <th>Event IDs</th>
            </tr>
          </thead>
          <tbody>
      `;for(const a of s.registrations){const i=a.eventIDs.map(l=>`<button class="select-event-btn badge info" data-event-id="${l}"
            style="cursor: pointer; border: none; margin: 0.125rem;"
            title="Click to select">${l}</button>`).join(" "),o=a.favorites.map(l=>`<span class="badge success" style="margin: 0.125rem;">${l}</span>`).join(" ");n+=`
          <tr>
            <td><code style="font-size: 0.75rem;">${a.tokenPrefix}</code></td>
            <td>${o||'<span style="color: var(--text-secondary);">none</span>'}</td>
            <td>${i||'<span style="color: var(--text-secondary);">none</span>'}</td>
          </tr>
        `}n+="</tbody></table>",e.innerHTML=n,e.querySelectorAll(".select-event-btn").forEach(a=>{a.addEventListener("click",i=>{var l;const o=i.target.dataset.eventId;if(o){const c=(l=this.container)==null?void 0:l.querySelector("#debug-event-id");c&&(c.value=o,c.focus(),$(`Selected: ${o}`,"success"))}})})}catch(s){const n=s instanceof Error?s.message:"Unknown error";e.innerHTML=`
        <div style="text-align: center; padding: 2rem; color: var(--danger-color);">
          <div style="font-size: 2rem; margin-bottom: 0.5rem;">⚠️</div>
          <div>Failed to load registrations: ${n}</div>
        </div>
      `}}async triggerAllPushToStart(e){var i,o,l,c,d,m,g,p;const t=e.textContent;e.disabled=!0,e.textContent="Starting all...";const s=(i=this.container)==null?void 0:i.querySelector("#debug-result"),n=((c=(l=(o=this.container)==null?void 0:o.querySelector("#debug-home-team"))==null?void 0:l.value)==null?void 0:c.trim())||"Debug Lions",a=((g=(m=(d=this.container)==null?void 0:d.querySelector("#debug-away-team"))==null?void 0:m.value)==null?void 0:g.trim())||"Debug Tigers";try{const h=await _.getPushToStartRegistrations(),u=new Set;for(const P of h.registrations)for(const L of P.eventIDs)u.add(L);if(u.size===0){$("No event IDs found in registrations","error");return}let b=0;const E=[],A=[],S=[];for(const P of u)try{const L=await _.triggerDebugPushToStart(P,n,a);b+=L.notified,E.push(`${P}: ${L.notified} device(s)${L.reason?` (${L.reason})`:""}`),L.trace&&A.push(`--- ${P} ---
${L.trace}`),(p=L.errors)!=null&&p.length&&S.push(...L.errors.map(F=>`${P}: ${F}`))}catch(L){const F=L instanceof Error?L.message:"Unknown error";E.push(`${P}: failed (${F})`)}s&&(s.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: ${b>0?"rgba(34,197,94,0.1)":"rgba(234,179,8,0.1)"};">
            <strong>${b>0?"✅":"⚠️"} Triggered ${u.size} event(s), notified ${b} device(s)</strong>
            <div style="margin-top: 0.5rem; font-family: monospace; font-size: 0.8rem; color: var(--text-secondary);">
              ${E.map(P=>`<div>${P}</div>`).join("")}
            </div>
            ${S.length?`<div style="margin-top: 0.5rem; color: var(--danger-color);"><strong>APNS Errors:</strong><pre style="margin: 0.25rem 0; font-size: 0.75rem; white-space: pre-wrap;">${S.join(`
`)}</pre></div>`:""}
            ${A.length?`<details style="margin-top: 0.75rem;"><summary style="cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);">Server Trace</summary><pre style="margin-top: 0.5rem; padding: 0.75rem; background: var(--bg-color); border: 1px solid var(--border-color); border-radius: 0.25rem; font-size: 0.7rem; white-space: pre-wrap; overflow-x: auto; color: var(--text-secondary);">${A.join(`

`)}</pre></details>`:""}
          </div>
        `),$(`Started all: ${b} device(s) notified across ${u.size} event(s)`,b>0?"success":"error")}catch(h){const u=h instanceof Error?h.message:"Unknown error";s&&(s.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: rgba(239,68,68,0.1); color: var(--danger-color);">
            <strong>❌ Failed:</strong> ${u}
          </div>
        `),$("Failed to trigger all push-to-starts","error")}finally{e.disabled=!1,e.textContent=t}}async triggerPushToStart(e){var o,l,c,d,m,g,p,h,u,b,E,A;const t=(c=(l=(o=this.container)==null?void 0:o.querySelector("#debug-event-id"))==null?void 0:l.value)==null?void 0:c.trim(),s=(g=(m=(d=this.container)==null?void 0:d.querySelector("#debug-home-team"))==null?void 0:m.value)==null?void 0:g.trim(),n=(u=(h=(p=this.container)==null?void 0:p.querySelector("#debug-away-team"))==null?void 0:h.value)==null?void 0:u.trim();if(!t){$("Event ID is required — select one from the registrations above","error");return}const a=e.textContent;e.disabled=!0,e.textContent="Sending...";const i=(b=this.container)==null?void 0:b.querySelector("#debug-result");try{const S=await _.triggerDebugPushToStart(t,s||"Debug Lions",n||"Debug Tigers");if(i){const P={no_registrations:"No push-to-start tokens found in Redis",apns_not_configured:"APNS not configured (missing APNSkeyID/TeamID env vars)",no_match:"Registrations exist but no favorites or event IDs matched"},L=S.reason?P[S.reason]||S.reason:"";i.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: ${S.notified>0?"rgba(34,197,94,0.1)":"rgba(234,179,8,0.1)"};">
            <strong>${S.notified>0?"✅":"⚠️"} Notified ${S.notified} device(s)</strong>
            ${(E=S.tokens)!=null&&E.length?`<div style="margin-top: 0.5rem; font-family: monospace; font-size: 0.8rem; color: var(--text-secondary);">Tokens: ${S.tokens.join(", ")}</div>`:""}
            ${L?`<div style="margin-top: 0.5rem; color: var(--warning-color, #eab308); font-weight: 600;">${L}</div>`:""}
            ${(A=S.errors)!=null&&A.length?`<div style="margin-top: 0.5rem; color: var(--danger-color);"><strong>APNS Errors:</strong><pre style="margin: 0.25rem 0; font-size: 0.75rem; white-space: pre-wrap;">${S.errors.join(`
`)}</pre></div>`:""}
            ${S.trace?`<details style="margin-top: 0.75rem;"><summary style="cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);">Server Trace</summary><pre style="margin-top: 0.5rem; padding: 0.75rem; background: var(--bg-color); border: 1px solid var(--border-color); border-radius: 0.25rem; font-size: 0.7rem; white-space: pre-wrap; overflow-x: auto; color: var(--text-secondary);">${S.trace}</pre></details>`:""}
          </div>
        `}$(`Push-to-start sent to ${S.notified} device(s)`,S.notified>0?"success":"error")}catch(S){const P=S instanceof Error?S.message:"Unknown error";i&&(i.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: rgba(239,68,68,0.1); color: var(--danger-color);">
            <strong>❌ Request Failed:</strong> ${P}
            <div style="margin-top: 0.5rem; font-size: 0.875rem; color: var(--text-secondary);">Make sure the Vapor server is running.</div>
          </div>
        `),$("Failed to trigger push-to-start","error")}finally{e.disabled=!1,e.textContent=a}}}class us{constructor(){f(this,"container",null);f(this,"eventSource",null);f(this,"consoleEl",null);f(this,"autoScroll",!0)}render(e){this.container=e,this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Vapor Server</h2>
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            <span id="server-badge" class="status-badge" style="padding: 0.25rem 0.75rem; border-radius: 999px; font-size: 0.75rem; font-weight: 700; text-transform: uppercase;">STOPPED</span>
            <span id="server-pid" style="font-size: 0.75rem; color: var(--text-secondary);"></span>
          </div>
        </div>

        <div style="display: flex; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap;">
          <button class="btn btn-primary" id="srv-start" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Start</button>
          <button class="btn btn-primary" id="srv-stop" style="padding: 0.5rem 1rem; font-size: 0.875rem;" disabled>Stop</button>
          <button class="btn btn-primary" id="srv-restart" style="padding: 0.5rem 1rem; font-size: 0.875rem;" disabled>Restart</button>
          <a class="btn" id="srv-open-admin" href="http://localhost:8080/admin/" target="_blank" rel="noopener" style="padding: 0.5rem 1rem; font-size: 0.875rem; pointer-events: none; opacity: 0.5;">Open Admin Page ↗</a>
          <button class="btn" id="srv-force-kill" style="padding: 0.5rem 1rem; font-size: 0.875rem; background: #dc2626; color: white; display: none;">Force Kill Port 8080</button>
          <div style="margin-left: auto; display: flex; align-items: center; gap: 0.5rem;">
            <label style="font-size: 0.75rem; color: var(--text-secondary); display: flex; align-items: center; gap: 0.25rem;">
              <input type="checkbox" id="srv-autoscroll" checked /> Auto-scroll
            </label>
            <button class="btn" id="srv-clear" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear</button>
          </div>
        </div>

        <div id="server-console" style="
          background: #0d1117;
          color: #c9d1d9;
          font-family: 'SF Mono', Menlo, Monaco, monospace;
          font-size: 0.75rem;
          line-height: 1.5;
          padding: 0.75rem;
          border-radius: 0.5rem;
          height: 500px;
          overflow-y: auto;
          white-space: pre-wrap;
          word-break: break-all;
        "></div>
      </div>
    `,this.consoleEl=document.getElementById("server-console"),document.getElementById("srv-start").addEventListener("click",()=>this.post("start")),document.getElementById("srv-stop").addEventListener("click",()=>this.post("stop")),document.getElementById("srv-restart").addEventListener("click",()=>this.post("restart")),document.getElementById("srv-force-kill").addEventListener("click",()=>this.post("force-kill")),document.getElementById("srv-clear").addEventListener("click",()=>{this.consoleEl&&(this.consoleEl.innerHTML="")}),document.getElementById("srv-autoscroll").addEventListener("change",t=>{this.autoScroll=t.target.checked}),this.loadHistory(),this.connectSSE(),this.checkExternalProcess()}stop(){var e;(e=this.eventSource)==null||e.close(),this.eventSource=null,this.container=null,this.consoleEl=null}async post(e){try{await fetch(`/__server/${e}`,{method:"POST"})}catch(t){console.error(`Server ${e} failed:`,t)}e==="force-kill"&&setTimeout(()=>this.checkExternalProcess(),500)}async loadHistory(){try{const t=await(await fetch("/__server/logs/history")).json();for(const s of t.lines)try{const n=JSON.parse(s);this.appendLine(n.line,n.stream)}catch{this.appendLine(s,"stdout")}}catch{}}connectSSE(){this.eventSource=new EventSource("/__server/logs"),this.eventSource.addEventListener("log",e=>{const t=JSON.parse(e.data);this.appendLine(t.line,t.stream)}),this.eventSource.addEventListener("state",e=>{const t=JSON.parse(e.data);this.updateState(t.state,t.pid,t.errorMessage)}),this.eventSource.onerror=()=>{}}appendLine(e,t){if(!this.consoleEl)return;const s=document.createElement("span");for(s.textContent=e+`
`,t==="stderr"&&(s.style.color="#f85149"),this.consoleEl.appendChild(s);this.consoleEl.childNodes.length>5e3;)this.consoleEl.removeChild(this.consoleEl.firstChild);this.autoScroll&&(this.consoleEl.scrollTop=this.consoleEl.scrollHeight)}updateState(e,t,s){const n=document.getElementById("server-badge"),a=document.getElementById("server-pid"),i=document.getElementById("srv-start"),o=document.getElementById("srv-stop"),l=document.getElementById("srv-restart");if(!n)return;const c={stopped:"#6b7280",building:"#f59e0b",running:"#22c55e",error:"#ef4444"};n.textContent=e.toUpperCase(),n.style.background=c[e]??"#6b7280",n.style.color="#fff",a&&(a.textContent=t?`PID ${t}`:""),i&&(i.disabled=e==="running"||e==="building"),o&&(o.disabled=e==="stopped"),l&&(l.disabled=e==="stopped");const d=document.getElementById("srv-open-admin");if(d){const m=e==="running";d.style.pointerEvents=m?"auto":"none",d.style.opacity=m?"1":"0.5"}s&&this.appendLine(`ERROR: ${s}`,"stderr")}async checkExternalProcess(){try{const t=await(await fetch("/__server/status")).json(),s=document.getElementById("srv-force-kill");if(!s)return;t.state==="stopped"?s.style.display="inline-block":s.style.display="none"}catch{}}}class ms{constructor(){f(this,"container",null);f(this,"ws",null);f(this,"entries",[]);f(this,"maxEntries",2e3);f(this,"paused",!1);f(this,"autoScroll",!0);f(this,"seenLabels",new Set);f(this,"filter",{level:"debug",labels:[],search:""});f(this,"searchDebounce",null)}render(e){this.container=e,this.entries=[],this.seenLabels=new Set,e.innerHTML=`
      <div class="logs-container">
        <div class="logs-toolbar">
          <div class="logs-toolbar-row">
            <div class="logs-level-filters">
              <button class="log-level-btn log-level-debug active" data-level="debug">DEBUG</button>
              <button class="log-level-btn log-level-info active" data-level="info">INFO</button>
              <button class="log-level-btn log-level-warning active" data-level="warning">WARN</button>
              <button class="log-level-btn log-level-error active" data-level="error">ERROR</button>
            </div>
            <input type="text" class="input logs-search" placeholder="Search logs..." id="logs-search" />
            <select class="select logs-label-select" id="logs-label-select" style="width: auto; min-width: 150px;">
              <option value="">All subsystems</option>
            </select>
            <div class="logs-actions">
              <button class="btn btn-secondary" id="logs-pause">Pause</button>
              <button class="btn btn-secondary" id="logs-clear">Clear</button>
              <span class="logs-count" id="logs-count">0 entries</span>
            </div>
          </div>
        </div>
        <div class="logs-list" id="logs-list"></div>
      </div>
    `,this.setupEventListeners(),this.connect()}stop(){this.disconnect()}setupEventListeners(){if(!this.container)return;this.container.querySelectorAll(".log-level-btn").forEach(i=>{i.addEventListener("click",()=>{i.classList.toggle("active"),this.updateMinLevel(),this.renderEntries()})});const e=this.container.querySelector("#logs-search");e==null||e.addEventListener("input",()=>{this.searchDebounce&&clearTimeout(this.searchDebounce),this.searchDebounce=setTimeout(()=>{this.filter.search=e.value,this.sendFilter(),this.renderEntries()},300)});const t=this.container.querySelector("#logs-label-select");t==null||t.addEventListener("change",()=>{this.filter.labels=t.value?[t.value]:[],this.sendFilter(),this.renderEntries()});const s=this.container.querySelector("#logs-pause");s==null||s.addEventListener("click",()=>{this.paused=!this.paused,s.textContent=this.paused?"Resume":"Pause"});const n=this.container.querySelector("#logs-clear");n==null||n.addEventListener("click",()=>{this.entries=[],this.renderEntries()});const a=this.container.querySelector("#logs-list");a==null||a.addEventListener("scroll",()=>{if(!a)return;const i=a;this.autoScroll=i.scrollHeight-i.scrollTop-i.clientHeight<50})}updateMinLevel(){var n;const e=["debug","info","warning","error"],t=(n=this.container)==null?void 0:n.querySelectorAll(".log-level-btn.active"),s=new Set;t==null||t.forEach(a=>{const i=a.dataset.level;i&&s.add(i)});for(const a of e)if(s.has(a)){this.filter.level=a,this.sendFilter();return}this.filter.level="error",this.sendFilter()}connect(){const t=`${window.location.protocol==="https:"?"wss:":"ws:"}//${window.location.host}/ws/logs`;try{this.ws=new WebSocket(t),this.ws.onmessage=s=>{if(!this.paused)try{const n=JSON.parse(s.data);n.type==="initial"&&Array.isArray(n.entries)?(this.entries=n.entries,n.entries.forEach(a=>this.seenLabels.add(a.label)),this.updateLabelSelect(),this.renderEntries()):n.type==="entry"&&n.entry&&this.addEntry(n.entry)}catch{}},this.ws.onclose=()=>{setTimeout(()=>{this.container&&this.connect()},3e3)}}catch{}}disconnect(){this.ws&&(this.ws.onclose=null,this.ws.close(),this.ws=null)}addEntry(e){var s;this.entries.push(e),this.entries.length>this.maxEntries&&(this.entries=this.entries.slice(-this.maxEntries));const t=!this.seenLabels.has(e.label);if(this.seenLabels.add(e.label),t&&this.updateLabelSelect(),this.matchesClientFilter(e)){const n=(s=this.container)==null?void 0:s.querySelector("#logs-list");n&&(n.appendChild(this.createEntryElement(e)),this.autoScroll&&(n.scrollTop=n.scrollHeight))}this.updateCount()}matchesClientFilter(e){var l;const t=["trace","debug","info","notice","warning","error","critical"],s=t.indexOf(e.level),n=t.indexOf(this.filter.level);if(s<n)return!1;const a=(l=this.container)==null?void 0:l.querySelectorAll(".log-level-btn.active"),i=new Set;a==null||a.forEach(c=>{const d=c.dataset.level;d&&i.add(d)});const o=e.level==="notice"?"info":e.level;return!(!i.has(o)||this.filter.labels.length>0&&!this.filter.labels.includes(e.label)||this.filter.search&&!e.message.toLowerCase().includes(this.filter.search.toLowerCase())&&!e.label.toLowerCase().includes(this.filter.search.toLowerCase()))}renderEntries(){var n;const e=(n=this.container)==null?void 0:n.querySelector("#logs-list");if(!e)return;const t=this.entries.filter(a=>this.matchesClientFilter(a)),s=document.createDocumentFragment();for(const a of t)s.appendChild(this.createEntryElement(a));e.innerHTML="",e.appendChild(s),this.autoScroll&&(e.scrollTop=e.scrollHeight),this.updateCount()}createEntryElement(e){const t=document.createElement("div");t.className=`log-entry log-level-${e.level}`;const s=new Date(e.timestamp).toLocaleTimeString("en-US",{hour12:!1,hour:"2-digit",minute:"2-digit",second:"2-digit",fractionalSecondDigits:3}),n=e.level.toUpperCase().padEnd(5),a=Object.keys(e.metadata).length>0?`<span class="log-metadata">${Object.entries(e.metadata).map(([i,o])=>`${i}=${o}`).join(" ")}</span>`:"";return t.innerHTML=`<span class="log-time">${s}</span><span class="log-level-badge log-badge-${e.level}">${n}</span><span class="log-label">${e.label}</span><span class="log-separator">│</span><span class="log-message">${this.escapeHtml(e.message)}</span>${a}`,Object.keys(e.metadata).length>0&&(t.style.cursor="pointer",t.addEventListener("click",()=>{const i=t.querySelector(".log-metadata-expanded");if(i)i.remove();else{const o=document.createElement("div");o.className="log-metadata-expanded",o.textContent=JSON.stringify(e.metadata,null,2),t.appendChild(o)}})),t}escapeHtml(e){const t=document.createElement("div");return t.textContent=e,t.innerHTML}updateLabelSelect(){var n;const e=(n=this.container)==null?void 0:n.querySelector("#logs-label-select");if(!e)return;const t=e.value,s=Array.from(this.seenLabels).sort();e.innerHTML='<option value="">All subsystems</option>'+s.map(a=>`<option value="${a}"${a===t?" selected":""}>${a}</option>`).join("")}updateCount(){var s,n,a;const e=(s=this.container)==null?void 0:s.querySelector("#logs-count");if(!e)return;const t=((a=(n=this.container)==null?void 0:n.querySelector("#logs-list"))==null?void 0:a.children.length)??0;e.textContent=`${t} / ${this.entries.length} entries`}sendFilter(){var e;((e=this.ws)==null?void 0:e.readyState)===WebSocket.OPEN&&this.ws.send(JSON.stringify({type:"filter",level:this.filter.level,labels:this.filter.labels.length>0?this.filter.labels:void 0,search:this.filter.search||void 0}))}}class gs{constructor(){f(this,"container",null);f(this,"target","prod");f(this,"loading",!1);f(this,"lastResponse",null);f(this,"lastRunAt",null)}render(e){var s;this.container=e,this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Parity Check</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <select id="parity-target" style="padding: 0.45rem 0.75rem; border-radius: 0.375rem; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color);">
              <option value="prod">Target: Prod</option>
              <option value="dev">Target: Dev (Tailscale)</option>
            </select>
            <button class="btn btn-primary" id="parity-run" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Run Comparison</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Compares this server's responses to the selected target for a fixed set of endpoints.
          Timestamp / volatile fields are stripped before diffing so live-scoreboard noise doesn't count.
        </p>
        <div id="parity-content"></div>
      </div>
    `;const t=this.container.querySelector("#parity-target");t&&t.addEventListener("change",()=>{this.target=t.value}),(s=this.container.querySelector("#parity-run"))==null||s.addEventListener("click",()=>this.runCheck()),this.renderBody()}stop(){}async runCheck(){if(!this.loading){this.loading=!0,this.renderBody();try{const e=await fetch(`/api/admin/parity?target=${encodeURIComponent(this.target)}`,{headers:{Accept:"application/json"}});if(!e.ok)throw new Error(`HTTP ${e.status} ${e.statusText}`);this.lastResponse=await e.json(),this.lastRunAt=new Date,$(`Parity: ${this.lastResponse.matches} match, ${this.lastResponse.mismatches} mismatch, ${this.lastResponse.errors} error`,this.lastResponse.mismatches+this.lastResponse.errors===0?"success":"error")}catch(e){const t=e instanceof Error?e.message:String(e);$(`Parity check failed: ${t}`,"error"),this.lastResponse=null}finally{this.loading=!1,this.renderBody()}}}renderBody(){var a;const e=(a=this.container)==null?void 0:a.querySelector("#parity-content");if(!e)return;if(this.loading){e.innerHTML='<div class="loading">Comparing…</div>';return}if(!this.lastResponse){e.innerHTML='<div style="color: var(--text-secondary); font-size: 0.875rem;">Click "Run Comparison" to fetch.</div>';return}const t=this.lastResponse,s=`
      <div style="display: flex; gap: 1.5rem; margin-bottom: 1rem; font-size: 0.875rem; color: var(--text-secondary);">
        <div><strong style="color: var(--text-color);">Local:</strong> <code>${Q(t.localBase)}</code></div>
        <div><strong style="color: var(--text-color);">Target:</strong> <code>${Q(t.targetBase)}</code></div>
        ${this.lastRunAt?`<div>ran at ${this.lastRunAt.toLocaleTimeString()}</div>`:""}
      </div>
      <div style="display: flex; gap: 0.75rem; margin-bottom: 1rem;">
        <span class="badge" style="background: rgba(34,197,94,0.15); color: #16a34a; padding: 0.25rem 0.6rem; border-radius: 999px; font-weight: 600; font-size: 0.85rem;">${t.matches} match</span>
        <span class="badge" style="background: rgba(234,179,8,0.15); color: #ca8a04; padding: 0.25rem 0.6rem; border-radius: 999px; font-weight: 600; font-size: 0.85rem;">${t.mismatches} mismatch</span>
        <span class="badge" style="background: rgba(239,68,68,0.15); color: #dc2626; padding: 0.25rem 0.6rem; border-radius: 999px; font-weight: 600; font-size: 0.85rem;">${t.errors} error</span>
      </div>
    `,n=t.results.map(i=>{const o=i.match?"✓":i.localStatus===200&&i.targetStatus===200?"≠":"⚠",l=i.match?"#16a34a":i.localStatus===200&&i.targetStatus===200?"#ca8a04":"#dc2626",c=i.diff?`<div style="color: var(--text-secondary); font-size: 0.8rem; margin-top: 0.25rem;">${Q(i.diff)}</div>`:"";return`
        <div style="border-bottom: 1px solid var(--border-color); padding: 0.6rem 0;">
          <div style="display: flex; justify-content: space-between; align-items: center; gap: 1rem;">
            <div style="display: flex; gap: 0.5rem; align-items: center; min-width: 0;">
              <span style="color: ${l}; font-weight: 700; font-size: 1.05rem;">${o}</span>
              <code style="font-size: 0.85rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${Q(i.endpoint)}</code>
            </div>
            <div style="color: var(--text-secondary); font-size: 0.8rem; white-space: nowrap;">
              ${i.localStatus}/${i.targetStatus} · ${Se(i.localBytes)}/${Se(i.targetBytes)}
            </div>
          </div>
          ${c}
        </div>
      `}).join("");e.innerHTML=s+n}}function Q(r){return r.replace(/[&<>"']/g,e=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[e])}function Se(r){return r<1024?`${r}B`:r<1024*1024?`${(r/1024).toFixed(1)}KB`:`${(r/(1024*1024)).toFixed(1)}MB`}class ps{constructor(){f(this,"container",null)}render(e){var t;this.container=e,e.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">World Cup 2026 Status</h2>
          <button class="btn btn-primary" id="wc-refresh" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Verifies the World Cup enrichment pipeline (group standings, knockout bracket, Golden Boot).
          Group count should be 12 once the 2026 group draw is published.
        </p>
        <div id="wc-content">Loading…</div>
      </div>
    `,(t=e.querySelector("#wc-refresh"))==null||t.addEventListener("click",()=>this.load()),this.load()}stop(){}async load(){var c,d,m;const e=(c=this.container)==null?void 0:c.querySelector("#wc-content");if(!e)return;e.innerHTML="Loading…";const[t,s,n]=await Promise.all([this.fetchJSON("/v2025/standings/4429"),this.fetchJSON("/v2025/worldcup/bracket"),this.fetchJSON("/v2025/worldcup/scorers")]),a=((m=(d=t==null?void 0:t.standings)==null?void 0:d.children)==null?void 0:m.filter(g=>{var p,h;return(((h=(p=g.standings)==null?void 0:p.entries)==null?void 0:h.length)??0)>0}))??[],i=(s==null?void 0:s.rounds)??[],o=i.reduce((g,p)=>{var h;return g+(((h=p.matches)==null?void 0:h.length)??0)},0),l=n??[];e.innerHTML=`
      <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin-bottom: 1rem;">
        ${this.stat("Groups",`${a.length}`,a.length===12?"ok":a.length>0?"warn":"bad")}
        ${this.stat("Bracket rounds",`${i.length}`,i.length>0?"ok":"warn")}
        ${this.stat("Knockout matches",`${o}`,o>0?"ok":"warn")}
        ${this.stat("Third place",s!=null&&s.thirdPlacePlayoff?"yes":"no",s!=null&&s.thirdPlacePlayoff?"ok":"warn")}
        ${this.stat("Top scorers",`${l.length}`,l.length>0?"ok":"warn")}
      </div>
      ${this.groupsTable(a)}
      ${this.roundsTable(i)}
      ${this.scorersTable(l)}
    `}async fetchJSON(e){try{const t=await fetch(e,{headers:{"Content-Type":"application/json"}});return t.ok?await t.json():null}catch{return null}}stat(e,t,s){return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.5rem; padding: 0.75rem;">
        <div style="font-size: 0.75rem; color: var(--text-secondary); text-transform: uppercase;">${e}</div>
        <div style="font-size: 1.5rem; font-weight: 700; color: ${s==="ok"?"var(--success-color, #1f8b3f)":s==="warn"?"var(--warning-color, #b8860b)":"var(--error-color, #d63b2f)"};">${t}</div>
      </div>
    `}groupsTable(e){return e.length===0?"":`<h3 style="margin-top:1rem;">Groups</h3><ul style="color: var(--text-secondary);">${e.map(s=>{var n,a;return`<li>${s.name??"Group"} — ${((a=(n=s.standings)==null?void 0:n.entries)==null?void 0:a.length)??0} teams</li>`}).join("")}</ul>`}roundsTable(e){return e.length===0?"":`<h3 style="margin-top:1rem;">Bracket</h3><ul style="color: var(--text-secondary);">${e.map(s=>{var n;return`<li>${s.roundName} — ${((n=s.matches)==null?void 0:n.length)??0} matches</li>`}).join("")}</ul>`}scorersTable(e){return e.length===0?"":`<h3 style="margin-top:1rem;">Golden Boot</h3><ol style="color: var(--text-secondary);">${e.slice(0,10).map(s=>`<li>${s.rank}. ${s.playerName} (${s.teamName}) — ${s.goals}</li>`).join("")}</ol>`}}const fs=["gate_hit","paywall_shown","paywall_dismissed","purchase_completed","trial_started","paywall_plan_selected","paywall_purchase_started","paywall_purchase_cancelled","paywall_purchase_failed","paywall_restore","activation_first_favorite","activation_notifications_enabled","ad_upsell_tapped","rating_prompt_shown","app_active"],ys=["appstore","testflight","debug","unknown","all","legacy"],vs={appstore:"App Store",testflight:"TestFlight",debug:"Debug builds",unknown:"Unknown (pre-channel builds)",all:"All channels",legacy:"Legacy (pre-channel counters)"},Te=["appstore","testflight","debug","unknown"],bs=["monthly","annual","lifetime"],ws={ios:"iOS",macos:"Mac",other:"Unknown"};class $s{constructor(){f(this,"container",null);f(this,"days",14);f(this,"channel","appstore")}render(e){var a;this.container=e;const t=ys.map(i=>`<option value="${i}"${i===this.channel?" selected":""}>${vs[i]}</option>`).join("");e.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Monetization Funnel</h2>
          <div style="display:flex; gap:0.5rem; align-items:center;">
            <select id="funnel-channel" style="padding:0.4rem 0.6rem; border-radius:6px;">${t}</select>
            <select id="funnel-range" style="padding:0.4rem 0.6rem; border-radius:6px;">
              <option value="7">Last 7 days</option>
              <option value="14" selected>Last 14 days</option>
              <option value="30">Last 30 days</option>
            </select>
            <button class="btn btn-primary" id="funnel-refresh" style="padding:0.5rem 1rem; font-size:0.875rem;">Refresh</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Client telemetry over the selected window. Event counters retain ~30 days;
          active-user and unique-install sets retain ~90 days.
        </p>
        <div id="funnel-body">Loading…</div>
      </div>
    `;const s=e.querySelector("#funnel-range");s.addEventListener("change",()=>{this.days=parseInt(s.value,10)||14,this.load()});const n=e.querySelector("#funnel-channel");n.addEventListener("change",()=>{this.channel=n.value,this.load()}),(a=e.querySelector("#funnel-refresh"))==null||a.addEventListener("click",()=>this.load()),this.load()}async load(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#funnel-body");if(e){e.innerHTML="Loading…";try{const s=await _.getTelemetry(this.days);e.innerHTML=this.renderBody(s)}catch(s){e.innerHTML=`<div class="badge danger">Failed to load telemetry: ${s instanceof Error?s.message:String(s)}</div>`}}}windowDays(e){const t=[];for(let s=e-this.days+1;s<=e;s++)t.push(String(s));return t}sumDays(e,t){return e?t.reduce((s,n)=>s+(e[n]||0),0):0}sources(e){const t=e.counters||{},s=e.channels||{};switch(this.channel){case"legacy":return[t];case"all":return[t,...Te.map(n=>s[n]||{})];default:return[s[this.channel]||{}]}}sum(e,t){const s=this.sources(e),n={};for(const a of fs)n[a]=s.reduce((i,o)=>i+this.sumDays(o[`client.${a}`],t),0);return n}breakouts(e,t,s){var i,o;const n=this.channel==="all"?Te:this.channel==="legacy"?[]:[this.channel],a={};for(const l of n){const c=((o=(i=e.dimensions)==null?void 0:i[l])==null?void 0:o[`client.${t}`])||{};for(const[d,m]of Object.entries(c))a[d]=(a[d]||0)+this.sumDays(m,s)}return Object.entries(a).filter(([,l])=>l>0).sort((l,c)=>c[1]-l[1])}pct(e,t){return t<=0?"—":`${(e/t*100).toFixed(1)}%`}renderBody(e){const t=this.windowDays(e.today),s=this.sum(e,t),n=s.purchase_completed+s.trial_started,a=[{label:"Pro gate hit",value:s.gate_hit,note:"user blocked by a Pro feature"},{label:"Paywall shown",value:s.paywall_shown,note:this.pct(s.paywall_shown,s.gate_hit)+" of gate hits"},{label:"Purchase or trial",value:n,note:this.pct(n,s.paywall_shown)+" of paywalls"}],i=this.renderBars(a),o=(l,c,d="")=>`
      <div class="stat-card">
        <div class="stat-value">${typeof c=="number"?c.toLocaleString():c}</div>
        <div class="stat-label">${l}${d?` <span style="color:var(--text-secondary)">(${d})</span>`:""}</div>
      </div>`;return`
      ${this.renderActiveUsers(e)}

      ${this.renderActivation(e)}

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Funnel (events)</h3>
      <div style="max-width:680px; margin-bottom:1.5rem;">${i}</div>

      ${this.renderPerUser(e)}

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Conversion (events)</h3>
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${o("Gate → Paywall",s.paywall_shown,this.pct(s.paywall_shown,s.gate_hit))}
        ${o("Paywall → Buy/Trial",n,this.pct(n,s.paywall_shown))}
        ${o("Purchases",s.purchase_completed)}
        ${o("Trials started",s.trial_started)}
        ${o("Paywall dismissed",s.paywall_dismissed,this.pct(s.paywall_dismissed,s.paywall_shown))}
        ${o("Ad “remove ads” taps",s.ad_upsell_tapped)}
      </div>

      ${this.renderPaywall(e,t,s)}

      ${this.renderBreakouts(e,t)}

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Activation & engagement</h3>
      <div class="stats-grid">
        ${o("First favorite added",s.activation_first_favorite)}
        ${o("Notifications enabled",s.activation_notifications_enabled)}
        ${o("Rating prompts shown",s.rating_prompt_shown)}
        ${o("app_active pings",s.app_active)}
      </div>
    `}renderBars(e){const t=Math.max(1,...e.map(s=>s.value));return e.map(s=>{const n=Math.max(2,Math.round(s.value/t*100));return`
          <div style="margin-bottom:0.85rem;">
            <div style="display:flex; justify-content:space-between; font-size:0.85rem; margin-bottom:0.25rem;">
              <span><strong>${s.label}</strong></span>
              <span style="color:var(--text-secondary);">${s.value.toLocaleString()} · ${s.note}</span>
            </div>
            <div style="background:var(--bg-secondary, #1e1e1e); border-radius:6px; overflow:hidden;">
              <div style="width:${n}%; background:var(--accent, #3b82f6); height:22px; border-radius:6px;"></div>
            </div>
          </div>`}).join("")}renderActiveUsers(e){var l;if(this.channel==="legacy")return"";const t=(l=e.activeUsers)==null?void 0:l[this.channel];if(!t)return"";const s=(c,d,m="")=>`
      <div class="stat-card">
        <div class="stat-value">${typeof d=="number"?d.toLocaleString():d}</div>
        <div class="stat-label">${c}${m?` <span style="color:var(--text-secondary)">(${m})</span>`:""}</div>
      </div>`,n=Object.entries(t.byPlatform||{}).filter(([,c])=>c.mau>0).map(([c,d])=>`<tr><td>${c}</td><td>${d.dau}</td><td>${d.wau}</td><td>${d.mau}</td></tr>`).join(""),a=Object.entries(t.daily||{}).sort((c,d)=>Number(c[0])-Number(d[0])),i=Math.max(1,...a.map(([,c])=>c)),o=a.map(([c,d])=>{const m=new Date(Number(c)*864e5).toISOString().slice(5,10),g=Math.max(2,Math.round(d/i*48));return`<div title="${m}: ${d}" style="flex:1; display:flex; flex-direction:column; justify-content:flex-end; align-items:center;">
            <div style="width:100%; height:${g}px; background:var(--accent, #3b82f6); border-radius:3px 3px 0 0;"></div>
          </div>`}).join("");return`
      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Active users (unique installs, UTC days)</h3>
      <div class="stats-grid" style="margin-bottom:1rem;">
        ${s("DAU",t.total.dau,"today, partial")}
        ${s("WAU",t.total.wau,"7 days")}
        ${s("MAU",t.total.mau,"30 days")}
        ${s("WAU / MAU",this.pct(t.total.wau,t.total.mau),"stickiness")}
      </div>
      <div style="display:flex; gap:2px; height:52px; max-width:680px; margin-bottom:0.5rem;">${o}</div>
      ${n?`<table style="max-width:420px; margin-bottom:1.5rem;">
              <thead><tr><th>Platform</th><th>DAU</th><th>WAU</th><th>MAU</th></tr></thead>
              <tbody>${n}</tbody>
            </table>`:'<p style="color:var(--text-secondary); margin-bottom:1.5rem;">No app_active pings yet for this channel.</p>'}
    `}renderActivation(e){var p,h;if(this.channel==="legacy")return"";const t=((p=e.uniqueInstalls)==null?void 0:p[this.channel])||{},s=e.activationFunnel||[],n=t["cohort.installs"]||0,a={activation_onboarding_started:"Onboarding started",activation_onboarding_completed:"Onboarding completed",activation_first_favorite:"First favorite",activation_notifications_granted:"Notifications allowed",activation_notifications_denied:"Notifications denied",activation_first_reminder_set:"First reminder set",activation_first_live_activity:"First Live Activity",activation_widget_installed:"Widget installed",activation_first_game_detail_opened:"First game detail opened"},o=[{label:"New installs",value:n}].concat(s.map(u=>({label:a[u]||u,value:t[`client.${u}`]||0}))).map(u=>`<tr><td>${u.label}</td><td>${u.value.toLocaleString()}</td><td>${u.label==="New installs"?"":this.pct(u.value,n)}</td></tr>`).join(""),l=this.breakouts(e,"activation_onboarding_completed",this.windowDays(e.today)).map(([u,b])=>`${u.split("=").slice(1).join("=")}: ${b}`).join(" · "),c=["d1","d7","d14","d30"],d=((h=e.retention)==null?void 0:h[this.channel])||[],m=(u,b)=>{if(!(b in u.retained))return'<td style="color:var(--text-secondary)">—</td>';const E=u.retained[b],A=u.complete[b]?"":' <span style="color:var(--text-secondary)" title="still filling in">…</span>';return`<td>${this.pct(E,u.installs)} <span style="color:var(--text-secondary)">(${E})</span>${A}</td>`},g=d.map(u=>`<tr><td>${new Date(u.weekStart*864e5).toISOString().slice(0,10)}</td><td>${u.installs.toLocaleString()}</td>${c.map(E=>m(u,E)).join("")}</tr>`).join("");return`
      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Activation (new installs, install-once events, ${e.windowDays}d)</h3>
      <table style="max-width:520px; margin-bottom:0.5rem;">
        <thead><tr><th>Step</th><th>Installs</th><th>% of new</th></tr></thead>
        <tbody>${o}</tbody>
      </table>
      ${l?`<p style="color:var(--text-secondary); margin-bottom:1rem;">Sports picked at onboarding: ${l}</p>`:""}

      <h3 style="margin:1rem 0 0.75rem; font-size:0.95rem;">Retention by install week (active exactly N days after install, UTC)</h3>
      ${g?`<table style="max-width:680px; margin-bottom:0.5rem;">
              <thead><tr><th>Week of</th><th>Installs</th><th>D1</th><th>D7</th><th>D14</th><th>D30</th></tr></thead>
              <tbody>${g}</tbody>
            </table>
            <p style="color:var(--text-secondary); margin-bottom:1.5rem;">… = some install days in the week haven't reached that mark yet. Upgraded (legacy) installs are excluded.</p>`:'<p style="color:var(--text-secondary); margin-bottom:1.5rem;">No retention data (server predates cohorts).</p>'}
    `}renderPerUser(e){var l,c,d;if(this.channel==="legacy")return"";const t=(l=e.uniqueInstalls)==null?void 0:l[this.channel];if(!t)return"";const s=m=>t[`client.${m}`]||0,n=s("paywall_shown"),a=s("purchase_or_trial"),i=((d=(c=e.activeUsers)==null?void 0:c[this.channel])==null?void 0:d.total.mau)||0,o=(m,g,p="")=>`
      <div class="stat-card">
        <div class="stat-value">${g.toLocaleString()}</div>
        <div class="stat-label">${m}${p?` <span style="color:var(--text-secondary)">(${p})</span>`:""}</div>
      </div>`;return`
      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Per-user conversion (unique installs, ${e.windowDays}d)</h3>
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${o("Users hitting a gate",s("gate_hit"))}
        ${o("Users shown paywall",n,this.pct(n,i)+" of MAU")}
        ${o("Users who bought/trialed",a,this.pct(a,n)+" of paywall users")}
        ${o("Purchasers",s("purchase_completed"))}
        ${o("Trialers",s("trial_started"))}
        ${o("Users adding a favorite",s("activation_first_favorite"),this.pct(s("activation_first_favorite"),i)+" of MAU")}
      </div>
    `}boughtDim(e,t,s){const n=this.dim(e,"purchase_completed",t,s);for(const[a,i]of Object.entries(this.dim(e,"trial_started",t,s)))n[a]=(n[a]||0)+i;return n}dim(e,t,s,n){const a={};for(const[i,o]of this.breakouts(e,t,n)){const[l,...c]=i.split("=");l===s&&(a[c.join("=")]=o)}return a}renderPaywall(e,t,s){var he,ue;const n='<h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Paywall</h3>';if(this.channel==="legacy")return`${n}<p style="color:var(--text-secondary); margin-bottom:1.5rem;">Paywall breakdowns are channel-tagged only — pick a channel.</p>`;const a=w=>`<span style="color:var(--text-secondary)">${w}</span>`,i=w=>w.toLocaleString(),o=w=>`<h4 style="margin:0.5rem 0 0.5rem; font-size:0.85rem;">${w}</h4>`,l=s.purchase_completed+s.trial_started,c=s.paywall_purchase_started,d=(w,C)=>C.some(D=>(D.other||0)>0)?[...w,"other"]:w,m=this.renderBars([{label:"Paywall shown",value:s.paywall_shown,note:"every open, incl. direct"},{label:"Purchase started",value:c,note:this.pct(c,s.paywall_shown)+" of shown"},{label:"Completed (purchase or trial)",value:l,note:`${this.pct(l,c)} of started · ${this.pct(l,s.paywall_shown)} of shown`}]),g=((ue=(he=e.uniqueInstalls)==null?void 0:he[this.channel])==null?void 0:ue["client.paywall_purchase_started"])||0,p=(w,C,D="")=>`
      <div class="stat-card">
        <div class="stat-value">${i(C)}</div>
        <div class="stat-label">${w}${D?` ${a(`(${D})`)}`:""}</div>
      </div>`,h=`
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${p("Purchase cancelled",s.paywall_purchase_cancelled,this.pct(s.paywall_purchase_cancelled,c)+" of started")}
        ${p("Purchase failed",s.paywall_purchase_failed,this.pct(s.paywall_purchase_failed,c)+" of started")}
        ${p("Users who started a purchase",g,"unique installs")}
        ${p("Plan row taps",s.paywall_plan_selected)}
      </div>`,u=this.dim(e,"paywall_plan_selected","plan",t),b=this.dim(e,"paywall_purchase_started","plan",t),E=this.dim(e,"paywall_purchase_cancelled","plan",t),A=this.dim(e,"paywall_purchase_failed","plan",t),S=this.boughtDim(e,"plan",t),L=`
      <table style="max-width:680px; margin-bottom:0.5rem;">
        <thead><tr><th>Plan</th><th>Selected</th><th>Started</th><th>Cancelled</th><th>Failed</th><th>Purchased</th><th>Started → bought</th></tr></thead>
        <tbody>${d(bs,[u,b,E,A,S]).map(w=>{const C=b[w]||0,D=S[w]||0;return`<tr><td>${w}</td><td>${i(u[w]||0)}</td><td>${i(C)}</td><td>${i(E[w]||0)}</td><td>${i(A[w]||0)}</td><td>${i(D)}</td><td>${this.pct(D,C)}</td></tr>`}).join("")}</tbody>
      </table>
      <p style="color:var(--text-secondary); margin-bottom:1.5rem;">“Selected” counts taps that switched plan rows. “Purchased” counts paid purchases and trials started from the paywall.</p>`,F=this.dim(e,"paywall_shown","trigger",t),I=this.dim(e,"paywall_purchase_started","trigger",t),Y=this.boughtDim(e,"trigger",t),y=this.dim(e,"paywall_dismissed","trigger",t),W=[...new Set([F,I,Y,y].flatMap(Object.keys))].sort((w,C)=>(F[C]||0)-(F[w]||0)).map(w=>{const C=F[w]||0,D=Y[w]||0;return`<tr><td>${w}</td><td>${i(C)}</td><td>${i(I[w]||0)}</td><td>${i(D)}</td><td>${this.pct(D,C)}</td><td>${i(y[w]||0)}</td></tr>`}).join(""),K=W?`<table style="max-width:680px; margin-bottom:1rem;">
          <thead><tr><th>Trigger</th><th>Shown</th><th>Started</th><th>Purchased</th><th>Shown → bought</th><th>Dismissed</th></tr></thead>
          <tbody>${W}</tbody>
        </table>`:'<p style="color:var(--text-secondary); margin-bottom:1rem;">No trigger-tagged paywall events yet.</p>',ie=Object.entries(this.dim(e,"paywall_shown","featured",t)).sort((w,C)=>C[1]-w[1]),Me=ie.length?`<table style="max-width:420px; margin-bottom:1.5rem;">
          <thead><tr><th>Featured (paywall led with)</th><th>Shown</th><th>% of shown</th></tr></thead>
          <tbody>${ie.map(([w,C])=>`<tr><td>${w}</td><td>${i(C)}</td><td>${this.pct(C,s.paywall_shown)}</td></tr>`).join("")}</tbody>
        </table>`:"",oe=this.dim(e,"paywall_shown","platform",t),le=this.dim(e,"paywall_purchase_started","platform",t),ce=this.boughtDim(e,"platform",t),Ae=`
      <table style="max-width:680px; margin-bottom:1.5rem;">
        <thead><tr><th>Platform</th><th>Shown</th><th>Started</th><th>Purchased</th><th>Shown → started</th><th>Shown → bought</th></tr></thead>
        <tbody>${d(["ios","macos"],[oe,le,ce]).map(w=>{const C=oe[w]||0,D=le[w]||0,X=ce[w]||0;return`<tr><td>${ws[w]||w}</td><td>${i(C)}</td><td>${i(D)}</td><td>${i(X)}</td><td>${this.pct(D,C)}</td><td>${this.pct(X,C)}</td></tr>`}).join("")}</tbody>
      </table>`,de=(w,C,D,X)=>{const Fe=d(Object.keys(C),[D]).map(se=>`<tr><td>${C[se]||"Other"}</td><td>${i(D[se]||0)}</td><td>${this.pct(D[se]||0,X)}</td></tr>`).join("");return`<table style="max-width:420px; margin-bottom:1rem;">
          <thead><tr><th>${w}</th><th>Count</th><th>%</th></tr></thead><tbody>${Fe}</tbody>
        </table>`},De=this.dim(e,"paywall_restore","result",t),_e=this.dim(e,"paywall_dismissed","outcome",t);return`
      ${n}
      <div style="max-width:680px; margin-bottom:1rem;">${m}</div>
      ${h}

      ${o("Plan mix")}
      ${L}

      ${o("By trigger")}
      ${K}
      ${Me}

      ${o("iOS vs Mac")}
      ${Ae}

      ${o("Outcomes")}
      <div style="display:flex; gap:1.5rem; flex-wrap:wrap; margin-bottom:1.5rem;">
        ${de("Restore result",{restored:"Restored",none:"Nothing to restore"},De,s.paywall_restore)}
        ${de("Dismissed",{purchased:"After purchase",closed:"Closed"},_e,s.paywall_dismissed)}
      </div>
    `}renderBreakouts(e,t){const s=(i,o)=>{if(o.length===0)return"";const l=o.map(([c,d])=>`<tr><td>${c.split("=").slice(1).join("=")}</td><td>${d.toLocaleString()}</td></tr>`).join("");return`<table style="max-width:420px; margin-bottom:1rem;">
          <thead><tr><th>${i}</th><th>Count</th></tr></thead><tbody>${l}</tbody>
        </table>`},n=(i,o)=>i.filter(([l])=>l.startsWith(`${o}=`)),a=s("Paywall trigger",n(this.breakouts(e,"paywall_shown",t),"trigger"))+s("Gate hit feature",n(this.breakouts(e,"gate_hit",t),"feature"));return a?`<h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Breakdowns</h3>${a}`:""}}class xs{constructor(){f(this,"currentView","");f(this,"components",new Map);f(this,"mainContent");this.mainContent=document.getElementById("main-content"),this.components.set("health",new rs),this.components.set("live",new ns),this.components.set("live-sources",new is),this.components.set("leagues",new os),this.components.set("gaps",new ls),this.components.set("redis",new cs),this.components.set("teams",new ds),this.components.set("debug",new hs),this.components.set("server",new us),this.components.set("logs",new ms),this.components.set("parity",new gs),this.components.set("worldcup",new ps),this.components.set("funnel",new $s),this.setupNavigation(),this.showView("health")}setupNavigation(){document.querySelectorAll(".nav-btn").forEach(t=>{t.addEventListener("click",s=>{const n=s.target.dataset.view;n&&this.showView(n)})})}showView(e){if(this.currentView===e)return;document.querySelectorAll(".nav-btn").forEach(n=>{n instanceof HTMLElement&&n.classList.toggle("active",n.dataset.view===e)});const t=this.components.get(this.currentView);t!=null&&t.stop&&t.stop(),this.currentView=e;const s=this.components.get(e);s&&(this.mainContent.innerHTML="",s.render(this.mainContent))}}document.addEventListener("DOMContentLoaded",()=>{new xs});

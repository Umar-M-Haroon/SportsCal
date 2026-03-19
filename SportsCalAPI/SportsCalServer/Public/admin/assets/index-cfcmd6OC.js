var ge=Object.defineProperty;var fe=(r,e,t)=>e in r?ge(r,e,{enumerable:!0,configurable:!0,writable:!0,value:t}):r[e]=t;var g=(r,e,t)=>fe(r,typeof e!="symbol"?e+"":e,t);(function(){const e=document.createElement("link").relList;if(e&&e.supports&&e.supports("modulepreload"))return;for(const n of document.querySelectorAll('link[rel="modulepreload"]'))s(n);new MutationObserver(n=>{for(const a of n)if(a.type==="childList")for(const i of a.addedNodes)i.tagName==="LINK"&&i.rel==="modulepreload"&&s(i)}).observe(document,{childList:!0,subtree:!0});function t(n){const a={};return n.integrity&&(a.integrity=n.integrity),n.referrerPolicy&&(a.referrerPolicy=n.referrerPolicy),n.crossOrigin==="use-credentials"?a.credentials="include":n.crossOrigin==="anonymous"?a.credentials="omit":a.credentials="same-origin",a}function s(n){if(n.ep)return;n.ep=!0;const a=t(n);fetch(n.href,a)}})();class pe{constructor(e=""){g(this,"baseUrl");this.baseUrl=e}async fetch(e,t){const s=await fetch(`${this.baseUrl}${e}`,{...t,headers:{"Content-Type":"application/json",...t==null?void 0:t.headers}});if(!s.ok)throw new Error(`API error: ${s.statusText}`);return s.json()}async getHealth(){return this.fetch("/api/admin/health")}async getMetrics(){return this.fetch("/api/admin/metrics")}async getRedisKeys(){return this.fetch("/api/admin/redis/keys")}async getRedisKey(e){return this.fetch(`/api/admin/redis/key/${encodeURIComponent(e)}`)}async getDataGaps(){return this.fetch("/api/admin/data-gaps")}async getLeagueStats(e){return this.fetch(`/api/admin/leagues/${e}/stats`)}async getSchedules(){return this.fetch("/v2025/schedules")}async getTeams(){return this.fetch("/v2025/teams")}async getLiveGames(){return this.fetch("/v2025/all-live-games")}async invalidateKey(e){return this.fetch(`/api/admin/redis/invalidate/${encodeURIComponent(e)}`,{method:"POST"})}async refreshSchedules(){return this.fetch("/api/admin/redis/refresh",{method:"POST"})}async forceRefresh(){return this.fetch("/api/admin/force-refresh",{method:"POST"})}async triggerJob(e){return this.fetch(`/api/admin/jobs/trigger/${e}`,{method:"POST"})}async clearAllCache(){return this.fetch("/api/admin/cache/all",{method:"DELETE"})}async getPushToStartRegistrations(){return this.fetch("/api/admin/push-to-start/registrations")}async getPushToStartDiagnostics(){return this.fetch("/api/admin/push-to-start/diagnostics")}async triggerDebugPushToStart(e,t,s){return this.fetch("/v2025/debug/trigger-push-to-start",{method:"POST",body:JSON.stringify({eventID:e,homeTeam:t,awayTeam:s})})}}const C=new pe;class ve{constructor(e="ws://localhost:8080/ws"){g(this,"ws",null);g(this,"reconnectTimer",null);g(this,"reconnectDelay",5e3);g(this,"url");g(this,"onMessageCallback",null);g(this,"onStatusChange",null);this.url=e}connect(e,t){var s;this.onMessageCallback=e,this.onStatusChange=t||null;try{const n=window.location.protocol==="https:"?this.url.replace("ws://","wss://"):this.url;this.ws=new WebSocket(n),this.ws.onopen=()=>{var a;console.log("WebSocket connected"),(a=this.onStatusChange)==null||a.call(this,!0),this.reconnectTimer&&(clearTimeout(this.reconnectTimer),this.reconnectTimer=null)},this.ws.onmessage=a=>{var i;try{const o=JSON.parse(a.data);(i=this.onMessageCallback)==null||i.call(this,o)}catch(o){console.error("Failed to parse WebSocket message:",o)}},this.ws.onerror=a=>{var i;console.error("WebSocket error:",a),(i=this.onStatusChange)==null||i.call(this,!1)},this.ws.onclose=()=>{var a;console.log("WebSocket disconnected"),(a=this.onStatusChange)==null||a.call(this,!1),this.scheduleReconnect()}}catch(n){console.error("Failed to connect WebSocket:",n),(s=this.onStatusChange)==null||s.call(this,!1),this.scheduleReconnect()}}scheduleReconnect(){this.reconnectTimer||(this.reconnectTimer=setTimeout(()=>{console.log("Attempting to reconnect WebSocket..."),this.onMessageCallback&&this.connect(this.onMessageCallback,this.onStatusChange||void 0)},this.reconnectDelay))}disconnect(){this.reconnectTimer&&(clearTimeout(this.reconnectTimer),this.reconnectTimer=null),this.ws&&(this.ws.close(),this.ws=null)}isConnected(){var e;return((e=this.ws)==null?void 0:e.readyState)===WebSocket.OPEN}}function $(r){const e=Object.prototype.toString.call(r);return r instanceof Date||typeof r=="object"&&e==="[object Date]"?new r.constructor(+r):typeof r=="number"||e==="[object Number]"||typeof r=="string"||e==="[object String]"?new Date(r):new Date(NaN)}function A(r,e){return r instanceof Date?new r.constructor(e):new Date(e)}const le=6048e5,ye=864e5,I=43200,Z=1440;let be={};function N(){return be}function G(r,e){var o,l,c,d;const t=N(),s=(e==null?void 0:e.weekStartsOn)??((l=(o=e==null?void 0:e.locale)==null?void 0:o.options)==null?void 0:l.weekStartsOn)??t.weekStartsOn??((d=(c=t.locale)==null?void 0:c.options)==null?void 0:d.weekStartsOn)??0,n=$(r),a=n.getDay(),i=(a<s?7:0)+a-s;return n.setDate(n.getDate()-i),n.setHours(0,0,0,0),n}function _(r){return G(r,{weekStartsOn:1})}function ce(r){const e=$(r),t=e.getFullYear(),s=A(r,0);s.setFullYear(t+1,0,4),s.setHours(0,0,0,0);const n=_(s),a=A(r,0);a.setFullYear(t,0,4),a.setHours(0,0,0,0);const i=_(a);return e.getTime()>=n.getTime()?t+1:e.getTime()>=i.getTime()?t:t-1}function ee(r){const e=$(r);return e.setHours(0,0,0,0),e}function Y(r){const e=$(r),t=new Date(Date.UTC(e.getFullYear(),e.getMonth(),e.getDate(),e.getHours(),e.getMinutes(),e.getSeconds(),e.getMilliseconds()));return t.setUTCFullYear(e.getFullYear()),+r-+t}function we(r,e){const t=ee(r),s=ee(e),n=+t-Y(t),a=+s-Y(s);return Math.round((n-a)/ye)}function xe(r){const e=ce(r),t=A(r,0);return t.setFullYear(e,0,4),t.setHours(0,0,0,0),_(t)}function B(r,e){const t=$(r),s=$(e),n=t.getTime()-s.getTime();return n<0?-1:n>0?1:n}function $e(r){return A(r,Date.now())}function Se(r){return r instanceof Date||typeof r=="object"&&Object.prototype.toString.call(r)==="[object Date]"}function Te(r){if(!Se(r)&&typeof r!="number")return!1;const e=$(r);return!isNaN(Number(e))}function Le(r,e){const t=$(r),s=$(e),n=t.getFullYear()-s.getFullYear(),a=t.getMonth()-s.getMonth();return n*12+a}function ke(r){return e=>{const s=(r?Math[r]:Math.trunc)(e);return s===0?0:s}}function Ee(r,e){return+$(r)-+$(e)}function Ce(r){const e=$(r);return e.setHours(23,59,59,999),e}function Me(r){const e=$(r),t=e.getMonth();return e.setFullYear(e.getFullYear(),t+1,0),e.setHours(23,59,59,999),e}function Pe(r){const e=$(r);return+Ce(e)==+Me(e)}function De(r,e){const t=$(r),s=$(e),n=B(t,s),a=Math.abs(Le(t,s));let i;if(a<1)i=0;else{t.getMonth()===1&&t.getDate()>27&&t.setDate(30),t.setMonth(t.getMonth()-n*a);let o=B(t,s)===-n;Pe($(r))&&a===1&&B(r,s)===1&&(o=!1),i=n*(a-Number(o))}return i===0?0:i}function Ae(r,e,t){const s=Ee(r,e)/1e3;return ke(t==null?void 0:t.roundingMethod)(s)}function Fe(r){const e=$(r),t=A(r,0);return t.setFullYear(e.getFullYear(),0,1),t.setHours(0,0,0,0),t}const He={lessThanXSeconds:{one:"less than a second",other:"less than {{count}} seconds"},xSeconds:{one:"1 second",other:"{{count}} seconds"},halfAMinute:"half a minute",lessThanXMinutes:{one:"less than a minute",other:"less than {{count}} minutes"},xMinutes:{one:"1 minute",other:"{{count}} minutes"},aboutXHours:{one:"about 1 hour",other:"about {{count}} hours"},xHours:{one:"1 hour",other:"{{count}} hours"},xDays:{one:"1 day",other:"{{count}} days"},aboutXWeeks:{one:"about 1 week",other:"about {{count}} weeks"},xWeeks:{one:"1 week",other:"{{count}} weeks"},aboutXMonths:{one:"about 1 month",other:"about {{count}} months"},xMonths:{one:"1 month",other:"{{count}} months"},aboutXYears:{one:"about 1 year",other:"about {{count}} years"},xYears:{one:"1 year",other:"{{count}} years"},overXYears:{one:"over 1 year",other:"over {{count}} years"},almostXYears:{one:"almost 1 year",other:"almost {{count}} years"}},Re=(r,e,t)=>{let s;const n=He[r];return typeof n=="string"?s=n:e===1?s=n.one:s=n.other.replace("{{count}}",e.toString()),t!=null&&t.addSuffix?t.comparison&&t.comparison>0?"in "+s:s+" ago":s};function K(r){return(e={})=>{const t=e.width?String(e.width):r.defaultWidth;return r.formats[t]||r.formats[r.defaultWidth]}}const ze={full:"EEEE, MMMM do, y",long:"MMMM do, y",medium:"MMM d, y",short:"MM/dd/yyyy"},Oe={full:"h:mm:ss a zzzz",long:"h:mm:ss a z",medium:"h:mm:ss a",short:"h:mm a"},We={full:"{{date}} 'at' {{time}}",long:"{{date}} 'at' {{time}}",medium:"{{date}}, {{time}}",short:"{{date}}, {{time}}"},Ge={date:K({formats:ze,defaultWidth:"full"}),time:K({formats:Oe,defaultWidth:"full"}),dateTime:K({formats:We,defaultWidth:"full"})},Ne={lastWeek:"'last' eeee 'at' p",yesterday:"'yesterday at' p",today:"'today at' p",tomorrow:"'tomorrow at' p",nextWeek:"eeee 'at' p",other:"P"},Ie=(r,e,t,s)=>Ne[r];function O(r){return(e,t)=>{const s=t!=null&&t.context?String(t.context):"standalone";let n;if(s==="formatting"&&r.formattingValues){const i=r.defaultFormattingWidth||r.defaultWidth,o=t!=null&&t.width?String(t.width):i;n=r.formattingValues[o]||r.formattingValues[i]}else{const i=r.defaultWidth,o=t!=null&&t.width?String(t.width):r.defaultWidth;n=r.values[o]||r.values[i]}const a=r.argumentCallback?r.argumentCallback(e):e;return n[a]}}const qe={narrow:["B","A"],abbreviated:["BC","AD"],wide:["Before Christ","Anno Domini"]},je={narrow:["1","2","3","4"],abbreviated:["Q1","Q2","Q3","Q4"],wide:["1st quarter","2nd quarter","3rd quarter","4th quarter"]},Be={narrow:["J","F","M","A","M","J","J","A","S","O","N","D"],abbreviated:["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"],wide:["January","February","March","April","May","June","July","August","September","October","November","December"]},_e={narrow:["S","M","T","W","T","F","S"],short:["Su","Mo","Tu","We","Th","Fr","Sa"],abbreviated:["Sun","Mon","Tue","Wed","Thu","Fri","Sat"],wide:["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]},Ye={narrow:{am:"a",pm:"p",midnight:"mi",noon:"n",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"},abbreviated:{am:"AM",pm:"PM",midnight:"midnight",noon:"noon",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"},wide:{am:"a.m.",pm:"p.m.",midnight:"midnight",noon:"noon",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"}},Ue={narrow:{am:"a",pm:"p",midnight:"mi",noon:"n",morning:"in the morning",afternoon:"in the afternoon",evening:"in the evening",night:"at night"},abbreviated:{am:"AM",pm:"PM",midnight:"midnight",noon:"noon",morning:"in the morning",afternoon:"in the afternoon",evening:"in the evening",night:"at night"},wide:{am:"a.m.",pm:"p.m.",midnight:"midnight",noon:"noon",morning:"in the morning",afternoon:"in the afternoon",evening:"in the evening",night:"at night"}},Ke=(r,e)=>{const t=Number(r),s=t%100;if(s>20||s<10)switch(s%10){case 1:return t+"st";case 2:return t+"nd";case 3:return t+"rd"}return t+"th"},Xe={ordinalNumber:Ke,era:O({values:qe,defaultWidth:"wide"}),quarter:O({values:je,defaultWidth:"wide",argumentCallback:r=>r-1}),month:O({values:Be,defaultWidth:"wide"}),day:O({values:_e,defaultWidth:"wide"}),dayPeriod:O({values:Ye,defaultWidth:"wide",formattingValues:Ue,defaultFormattingWidth:"wide"})};function W(r){return(e,t={})=>{const s=t.width,n=s&&r.matchPatterns[s]||r.matchPatterns[r.defaultMatchWidth],a=e.match(n);if(!a)return null;const i=a[0],o=s&&r.parsePatterns[s]||r.parsePatterns[r.defaultParseWidth],l=Array.isArray(o)?Je(o,h=>h.test(i)):Ve(o,h=>h.test(i));let c;c=r.valueCallback?r.valueCallback(l):l,c=t.valueCallback?t.valueCallback(c):c;const d=e.slice(i.length);return{value:c,rest:d}}}function Ve(r,e){for(const t in r)if(Object.prototype.hasOwnProperty.call(r,t)&&e(r[t]))return t}function Je(r,e){for(let t=0;t<r.length;t++)if(e(r[t]))return t}function Qe(r){return(e,t={})=>{const s=e.match(r.matchPattern);if(!s)return null;const n=s[0],a=e.match(r.parsePattern);if(!a)return null;let i=r.valueCallback?r.valueCallback(a[0]):a[0];i=t.valueCallback?t.valueCallback(i):i;const o=e.slice(n.length);return{value:i,rest:o}}}const Ze=/^(\d+)(th|st|nd|rd)?/i,et=/\d+/i,tt={narrow:/^(b|a)/i,abbreviated:/^(b\.?\s?c\.?|b\.?\s?c\.?\s?e\.?|a\.?\s?d\.?|c\.?\s?e\.?)/i,wide:/^(before christ|before common era|anno domini|common era)/i},st={any:[/^b/i,/^(a|c)/i]},rt={narrow:/^[1234]/i,abbreviated:/^q[1234]/i,wide:/^[1234](th|st|nd|rd)? quarter/i},nt={any:[/1/i,/2/i,/3/i,/4/i]},at={narrow:/^[jfmasond]/i,abbreviated:/^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i,wide:/^(january|february|march|april|may|june|july|august|september|october|november|december)/i},it={narrow:[/^j/i,/^f/i,/^m/i,/^a/i,/^m/i,/^j/i,/^j/i,/^a/i,/^s/i,/^o/i,/^n/i,/^d/i],any:[/^ja/i,/^f/i,/^mar/i,/^ap/i,/^may/i,/^jun/i,/^jul/i,/^au/i,/^s/i,/^o/i,/^n/i,/^d/i]},ot={narrow:/^[smtwf]/i,short:/^(su|mo|tu|we|th|fr|sa)/i,abbreviated:/^(sun|mon|tue|wed|thu|fri|sat)/i,wide:/^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)/i},lt={narrow:[/^s/i,/^m/i,/^t/i,/^w/i,/^t/i,/^f/i,/^s/i],any:[/^su/i,/^m/i,/^tu/i,/^w/i,/^th/i,/^f/i,/^sa/i]},ct={narrow:/^(a|p|mi|n|(in the|at) (morning|afternoon|evening|night))/i,any:/^([ap]\.?\s?m\.?|midnight|noon|(in the|at) (morning|afternoon|evening|night))/i},dt={any:{am:/^a/i,pm:/^p/i,midnight:/^mi/i,noon:/^no/i,morning:/morning/i,afternoon:/afternoon/i,evening:/evening/i,night:/night/i}},ut={ordinalNumber:Qe({matchPattern:Ze,parsePattern:et,valueCallback:r=>parseInt(r,10)}),era:W({matchPatterns:tt,defaultMatchWidth:"wide",parsePatterns:st,defaultParseWidth:"any"}),quarter:W({matchPatterns:rt,defaultMatchWidth:"wide",parsePatterns:nt,defaultParseWidth:"any",valueCallback:r=>r+1}),month:W({matchPatterns:at,defaultMatchWidth:"wide",parsePatterns:it,defaultParseWidth:"any"}),day:W({matchPatterns:ot,defaultMatchWidth:"wide",parsePatterns:lt,defaultParseWidth:"any"}),dayPeriod:W({matchPatterns:ct,defaultMatchWidth:"any",parsePatterns:dt,defaultParseWidth:"any"})},de={code:"en-US",formatDistance:Re,formatLong:Ge,formatRelative:Ie,localize:Xe,match:ut,options:{weekStartsOn:0,firstWeekContainsDate:1}};function ht(r){const e=$(r);return we(e,Fe(e))+1}function mt(r){const e=$(r),t=+_(e)-+xe(e);return Math.round(t/le)+1}function ue(r,e){var d,h,u,f;const t=$(r),s=t.getFullYear(),n=N(),a=(e==null?void 0:e.firstWeekContainsDate)??((h=(d=e==null?void 0:e.locale)==null?void 0:d.options)==null?void 0:h.firstWeekContainsDate)??n.firstWeekContainsDate??((f=(u=n.locale)==null?void 0:u.options)==null?void 0:f.firstWeekContainsDate)??1,i=A(r,0);i.setFullYear(s+1,0,a),i.setHours(0,0,0,0);const o=G(i,e),l=A(r,0);l.setFullYear(s,0,a),l.setHours(0,0,0,0);const c=G(l,e);return t.getTime()>=o.getTime()?s+1:t.getTime()>=c.getTime()?s:s-1}function gt(r,e){var o,l,c,d;const t=N(),s=(e==null?void 0:e.firstWeekContainsDate)??((l=(o=e==null?void 0:e.locale)==null?void 0:o.options)==null?void 0:l.firstWeekContainsDate)??t.firstWeekContainsDate??((d=(c=t.locale)==null?void 0:c.options)==null?void 0:d.firstWeekContainsDate)??1,n=ue(r,e),a=A(r,0);return a.setFullYear(n,0,s),a.setHours(0,0,0,0),G(a,e)}function ft(r,e){const t=$(r),s=+G(t,e)-+gt(t,e);return Math.round(s/le)+1}function w(r,e){const t=r<0?"-":"",s=Math.abs(r).toString().padStart(e,"0");return t+s}const D={y(r,e){const t=r.getFullYear(),s=t>0?t:1-t;return w(e==="yy"?s%100:s,e.length)},M(r,e){const t=r.getMonth();return e==="M"?String(t+1):w(t+1,2)},d(r,e){return w(r.getDate(),e.length)},a(r,e){const t=r.getHours()/12>=1?"pm":"am";switch(e){case"a":case"aa":return t.toUpperCase();case"aaa":return t;case"aaaaa":return t[0];case"aaaa":default:return t==="am"?"a.m.":"p.m."}},h(r,e){return w(r.getHours()%12||12,e.length)},H(r,e){return w(r.getHours(),e.length)},m(r,e){return w(r.getMinutes(),e.length)},s(r,e){return w(r.getSeconds(),e.length)},S(r,e){const t=e.length,s=r.getMilliseconds(),n=Math.trunc(s*Math.pow(10,t-3));return w(n,e.length)}},R={midnight:"midnight",noon:"noon",morning:"morning",afternoon:"afternoon",evening:"evening",night:"night"},te={G:function(r,e,t){const s=r.getFullYear()>0?1:0;switch(e){case"G":case"GG":case"GGG":return t.era(s,{width:"abbreviated"});case"GGGGG":return t.era(s,{width:"narrow"});case"GGGG":default:return t.era(s,{width:"wide"})}},y:function(r,e,t){if(e==="yo"){const s=r.getFullYear(),n=s>0?s:1-s;return t.ordinalNumber(n,{unit:"year"})}return D.y(r,e)},Y:function(r,e,t,s){const n=ue(r,s),a=n>0?n:1-n;if(e==="YY"){const i=a%100;return w(i,2)}return e==="Yo"?t.ordinalNumber(a,{unit:"year"}):w(a,e.length)},R:function(r,e){const t=ce(r);return w(t,e.length)},u:function(r,e){const t=r.getFullYear();return w(t,e.length)},Q:function(r,e,t){const s=Math.ceil((r.getMonth()+1)/3);switch(e){case"Q":return String(s);case"QQ":return w(s,2);case"Qo":return t.ordinalNumber(s,{unit:"quarter"});case"QQQ":return t.quarter(s,{width:"abbreviated",context:"formatting"});case"QQQQQ":return t.quarter(s,{width:"narrow",context:"formatting"});case"QQQQ":default:return t.quarter(s,{width:"wide",context:"formatting"})}},q:function(r,e,t){const s=Math.ceil((r.getMonth()+1)/3);switch(e){case"q":return String(s);case"qq":return w(s,2);case"qo":return t.ordinalNumber(s,{unit:"quarter"});case"qqq":return t.quarter(s,{width:"abbreviated",context:"standalone"});case"qqqqq":return t.quarter(s,{width:"narrow",context:"standalone"});case"qqqq":default:return t.quarter(s,{width:"wide",context:"standalone"})}},M:function(r,e,t){const s=r.getMonth();switch(e){case"M":case"MM":return D.M(r,e);case"Mo":return t.ordinalNumber(s+1,{unit:"month"});case"MMM":return t.month(s,{width:"abbreviated",context:"formatting"});case"MMMMM":return t.month(s,{width:"narrow",context:"formatting"});case"MMMM":default:return t.month(s,{width:"wide",context:"formatting"})}},L:function(r,e,t){const s=r.getMonth();switch(e){case"L":return String(s+1);case"LL":return w(s+1,2);case"Lo":return t.ordinalNumber(s+1,{unit:"month"});case"LLL":return t.month(s,{width:"abbreviated",context:"standalone"});case"LLLLL":return t.month(s,{width:"narrow",context:"standalone"});case"LLLL":default:return t.month(s,{width:"wide",context:"standalone"})}},w:function(r,e,t,s){const n=ft(r,s);return e==="wo"?t.ordinalNumber(n,{unit:"week"}):w(n,e.length)},I:function(r,e,t){const s=mt(r);return e==="Io"?t.ordinalNumber(s,{unit:"week"}):w(s,e.length)},d:function(r,e,t){return e==="do"?t.ordinalNumber(r.getDate(),{unit:"date"}):D.d(r,e)},D:function(r,e,t){const s=ht(r);return e==="Do"?t.ordinalNumber(s,{unit:"dayOfYear"}):w(s,e.length)},E:function(r,e,t){const s=r.getDay();switch(e){case"E":case"EE":case"EEE":return t.day(s,{width:"abbreviated",context:"formatting"});case"EEEEE":return t.day(s,{width:"narrow",context:"formatting"});case"EEEEEE":return t.day(s,{width:"short",context:"formatting"});case"EEEE":default:return t.day(s,{width:"wide",context:"formatting"})}},e:function(r,e,t,s){const n=r.getDay(),a=(n-s.weekStartsOn+8)%7||7;switch(e){case"e":return String(a);case"ee":return w(a,2);case"eo":return t.ordinalNumber(a,{unit:"day"});case"eee":return t.day(n,{width:"abbreviated",context:"formatting"});case"eeeee":return t.day(n,{width:"narrow",context:"formatting"});case"eeeeee":return t.day(n,{width:"short",context:"formatting"});case"eeee":default:return t.day(n,{width:"wide",context:"formatting"})}},c:function(r,e,t,s){const n=r.getDay(),a=(n-s.weekStartsOn+8)%7||7;switch(e){case"c":return String(a);case"cc":return w(a,e.length);case"co":return t.ordinalNumber(a,{unit:"day"});case"ccc":return t.day(n,{width:"abbreviated",context:"standalone"});case"ccccc":return t.day(n,{width:"narrow",context:"standalone"});case"cccccc":return t.day(n,{width:"short",context:"standalone"});case"cccc":default:return t.day(n,{width:"wide",context:"standalone"})}},i:function(r,e,t){const s=r.getDay(),n=s===0?7:s;switch(e){case"i":return String(n);case"ii":return w(n,e.length);case"io":return t.ordinalNumber(n,{unit:"day"});case"iii":return t.day(s,{width:"abbreviated",context:"formatting"});case"iiiii":return t.day(s,{width:"narrow",context:"formatting"});case"iiiiii":return t.day(s,{width:"short",context:"formatting"});case"iiii":default:return t.day(s,{width:"wide",context:"formatting"})}},a:function(r,e,t){const n=r.getHours()/12>=1?"pm":"am";switch(e){case"a":case"aa":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"});case"aaa":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"}).toLowerCase();case"aaaaa":return t.dayPeriod(n,{width:"narrow",context:"formatting"});case"aaaa":default:return t.dayPeriod(n,{width:"wide",context:"formatting"})}},b:function(r,e,t){const s=r.getHours();let n;switch(s===12?n=R.noon:s===0?n=R.midnight:n=s/12>=1?"pm":"am",e){case"b":case"bb":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"});case"bbb":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"}).toLowerCase();case"bbbbb":return t.dayPeriod(n,{width:"narrow",context:"formatting"});case"bbbb":default:return t.dayPeriod(n,{width:"wide",context:"formatting"})}},B:function(r,e,t){const s=r.getHours();let n;switch(s>=17?n=R.evening:s>=12?n=R.afternoon:s>=4?n=R.morning:n=R.night,e){case"B":case"BB":case"BBB":return t.dayPeriod(n,{width:"abbreviated",context:"formatting"});case"BBBBB":return t.dayPeriod(n,{width:"narrow",context:"formatting"});case"BBBB":default:return t.dayPeriod(n,{width:"wide",context:"formatting"})}},h:function(r,e,t){if(e==="ho"){let s=r.getHours()%12;return s===0&&(s=12),t.ordinalNumber(s,{unit:"hour"})}return D.h(r,e)},H:function(r,e,t){return e==="Ho"?t.ordinalNumber(r.getHours(),{unit:"hour"}):D.H(r,e)},K:function(r,e,t){const s=r.getHours()%12;return e==="Ko"?t.ordinalNumber(s,{unit:"hour"}):w(s,e.length)},k:function(r,e,t){let s=r.getHours();return s===0&&(s=24),e==="ko"?t.ordinalNumber(s,{unit:"hour"}):w(s,e.length)},m:function(r,e,t){return e==="mo"?t.ordinalNumber(r.getMinutes(),{unit:"minute"}):D.m(r,e)},s:function(r,e,t){return e==="so"?t.ordinalNumber(r.getSeconds(),{unit:"second"}):D.s(r,e)},S:function(r,e){return D.S(r,e)},X:function(r,e,t){const s=r.getTimezoneOffset();if(s===0)return"Z";switch(e){case"X":return re(s);case"XXXX":case"XX":return F(s);case"XXXXX":case"XXX":default:return F(s,":")}},x:function(r,e,t){const s=r.getTimezoneOffset();switch(e){case"x":return re(s);case"xxxx":case"xx":return F(s);case"xxxxx":case"xxx":default:return F(s,":")}},O:function(r,e,t){const s=r.getTimezoneOffset();switch(e){case"O":case"OO":case"OOO":return"GMT"+se(s,":");case"OOOO":default:return"GMT"+F(s,":")}},z:function(r,e,t){const s=r.getTimezoneOffset();switch(e){case"z":case"zz":case"zzz":return"GMT"+se(s,":");case"zzzz":default:return"GMT"+F(s,":")}},t:function(r,e,t){const s=Math.trunc(r.getTime()/1e3);return w(s,e.length)},T:function(r,e,t){const s=r.getTime();return w(s,e.length)}};function se(r,e=""){const t=r>0?"-":"+",s=Math.abs(r),n=Math.trunc(s/60),a=s%60;return a===0?t+String(n):t+String(n)+e+w(a,2)}function re(r,e){return r%60===0?(r>0?"-":"+")+w(Math.abs(r)/60,2):F(r,e)}function F(r,e=""){const t=r>0?"-":"+",s=Math.abs(r),n=w(Math.trunc(s/60),2),a=w(s%60,2);return t+n+e+a}const ne=(r,e)=>{switch(r){case"P":return e.date({width:"short"});case"PP":return e.date({width:"medium"});case"PPP":return e.date({width:"long"});case"PPPP":default:return e.date({width:"full"})}},he=(r,e)=>{switch(r){case"p":return e.time({width:"short"});case"pp":return e.time({width:"medium"});case"ppp":return e.time({width:"long"});case"pppp":default:return e.time({width:"full"})}},pt=(r,e)=>{const t=r.match(/(P+)(p+)?/)||[],s=t[1],n=t[2];if(!n)return ne(r,e);let a;switch(s){case"P":a=e.dateTime({width:"short"});break;case"PP":a=e.dateTime({width:"medium"});break;case"PPP":a=e.dateTime({width:"long"});break;case"PPPP":default:a=e.dateTime({width:"full"});break}return a.replace("{{date}}",ne(s,e)).replace("{{time}}",he(n,e))},vt={p:he,P:pt},yt=/^D+$/,bt=/^Y+$/,wt=["D","DD","YY","YYYY"];function xt(r){return yt.test(r)}function $t(r){return bt.test(r)}function St(r,e,t){const s=Tt(r,e,t);if(console.warn(s),wt.includes(r))throw new RangeError(s)}function Tt(r,e,t){const s=r[0]==="Y"?"years":"days of the month";return`Use \`${r.toLowerCase()}\` instead of \`${r}\` (in \`${e}\`) for formatting ${s} to the input \`${t}\`; see: https://github.com/date-fns/date-fns/blob/master/docs/unicodeTokens.md`}const Lt=/[yYQqMLwIdDecihHKkms]o|(\w)\1*|''|'(''|[^'])+('|$)|./g,kt=/P+p+|P+|p+|''|'(''|[^'])+('|$)|./g,Et=/^'([^]*?)'?$/,Ct=/''/g,Mt=/[a-zA-Z]/;function Pt(r,e,t){var d,h,u,f;const s=N(),n=s.locale??de,a=s.firstWeekContainsDate??((h=(d=s.locale)==null?void 0:d.options)==null?void 0:h.firstWeekContainsDate)??1,i=s.weekStartsOn??((f=(u=s.locale)==null?void 0:u.options)==null?void 0:f.weekStartsOn)??0,o=$(r);if(!Te(o))throw new RangeError("Invalid time value");let l=e.match(kt).map(m=>{const p=m[0];if(p==="p"||p==="P"){const T=vt[p];return T(m,n.formatLong)}return m}).join("").match(Lt).map(m=>{if(m==="''")return{isToken:!1,value:"'"};const p=m[0];if(p==="'")return{isToken:!1,value:Dt(m)};if(te[p])return{isToken:!0,value:m};if(p.match(Mt))throw new RangeError("Format string contains an unescaped latin alphabet character `"+p+"`");return{isToken:!1,value:m}});n.localize.preprocessor&&(l=n.localize.preprocessor(o,l));const c={firstWeekContainsDate:a,weekStartsOn:i,locale:n};return l.map(m=>{if(!m.isToken)return m.value;const p=m.value;($t(p)||xt(p))&&St(p,e,String(r));const T=te[p[0]];return T(o,p,n.localize,c)}).join("")}function Dt(r){const e=r.match(Et);return e?e[1].replace(Ct,"'"):r}function At(r,e,t){const s=N(),n=(t==null?void 0:t.locale)??s.locale??de,a=2520,i=B(r,e);if(isNaN(i))throw new RangeError("Invalid time value");const o=Object.assign({},t,{addSuffix:t==null?void 0:t.addSuffix,comparison:i});let l,c;i>0?(l=$(e),c=$(r)):(l=$(r),c=$(e));const d=Ae(c,l),h=(Y(c)-Y(l))/1e3,u=Math.round((d-h)/60);let f;if(u<2)return t!=null&&t.includeSeconds?d<5?n.formatDistance("lessThanXSeconds",5,o):d<10?n.formatDistance("lessThanXSeconds",10,o):d<20?n.formatDistance("lessThanXSeconds",20,o):d<40?n.formatDistance("halfAMinute",0,o):d<60?n.formatDistance("lessThanXMinutes",1,o):n.formatDistance("xMinutes",1,o):u===0?n.formatDistance("lessThanXMinutes",1,o):n.formatDistance("xMinutes",u,o);if(u<45)return n.formatDistance("xMinutes",u,o);if(u<90)return n.formatDistance("aboutXHours",1,o);if(u<Z){const m=Math.round(u/60);return n.formatDistance("aboutXHours",m,o)}else{if(u<a)return n.formatDistance("xDays",1,o);if(u<I){const m=Math.round(u/Z);return n.formatDistance("xDays",m,o)}else if(u<I*2)return f=Math.round(u/I),n.formatDistance("aboutXMonths",f,o)}if(f=De(c,l),f<12){const m=Math.round(u/I);return n.formatDistance("xMonths",m,o)}else{const m=f%12,p=Math.trunc(f/12);return m<3?n.formatDistance("aboutXYears",p,o):m<9?n.formatDistance("overXYears",p,o):n.formatDistance("almostXYears",p+1,o)}}function Ft(r,e){return At(r,$e(r),e)}function ae(r){if(!r)return"N/A";const e=["B","KB","MB","GB"];let t=r,s=0;for(;t>=1024&&s<e.length-1;)t/=1024,s++;return`${t.toFixed(2)} ${e[s]}`}function X(r){if(!r)return"Never";try{const e=new Date(r);return Ft(e,{addSuffix:!0})}catch{return"Invalid date"}}function q(r){if(!r)return"N/A";try{const e=new Date(r);return Pt(e,"MMM d, yyyy HH:mm:ss")}catch{return"Invalid date"}}function ie(r){if(r==null||r<0)return"No expiration";const e=Math.floor(r/3600),t=Math.floor(r%3600/60),s=r%60;return e>0?`${e}h ${t}m ${s}s`:t>0?`${t}m ${s}s`:`${s}s`}function oe(r){return`${(r*100).toFixed(1)}%`}function H(r){if(!r)return{text:"Unknown",class:"badge"};const e=r.toLowerCase();return["ft","aot","final","post","completed","finished","match finished"].some(t=>e.includes(t))?{text:"Final",class:"badge info"}:["ns","pre","scheduled","not started"].some(t=>e.includes(t))?{text:"Upcoming",class:"badge warning"}:["live","active","in progress","in play"].some(t=>e.includes(t))||/^\d/.test(e)?{text:"Live",class:"badge success"}:{text:r,class:"badge"}}function x(r,e="success"){const t=document.createElement("div");t.className=`toast ${e}`,t.textContent=r,document.body.appendChild(t),setTimeout(()=>{t.remove()},5e3)}function Ht(r){try{const e=JSON.parse(r);return V(e,0)}catch{return r.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}}function V(r,e){const t="  ".repeat(e),s="  ".repeat(e+1);if(r===null)return'<span class="json-null">null</span>';if(typeof r=="boolean")return`<span class="json-boolean">${r}</span>`;if(typeof r=="number")return`<span class="json-number">${r}</span>`;if(typeof r=="string")return`<span class="json-string">"${r.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;")}"</span>`;if(Array.isArray(r)){if(r.length===0)return'<span class="json-punctuation">[]</span>';const n=`collapse-${Math.random().toString(36).substr(2,9)}`,a=r.length===1?"1 item":`${r.length} items`;let i='<span class="json-punctuation">[</span>';return i+=`<span class="json-collapse-btn" data-target="${n}" style="cursor: pointer; color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem;">▼ ${a}</span>`,i+=`
<div id="${n}" class="json-collapsible">`,r.forEach((o,l)=>{i+=s,i+=V(o,e+1),l<r.length-1&&(i+='<span class="json-punctuation">,</span>'),i+=`
`}),i+=`</div>${t}<span class="json-punctuation">]</span>`,i}if(typeof r=="object"){const n=Object.keys(r);if(n.length===0)return'<span class="json-punctuation">{}</span>';const a=`collapse-${Math.random().toString(36).substr(2,9)}`,i=n.length===1?"1 property":`${n.length} properties`;let o='<span class="json-punctuation">{</span>';return o+=`<span class="json-collapse-btn" data-target="${a}" style="cursor: pointer; color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem;">▼ ${i}</span>`,o+=`
<div id="${a}" class="json-collapsible">`,n.forEach((l,c)=>{const d=l.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");o+=s,o+=`<span class="json-key">"${d}"</span><span class="json-punctuation">: </span>`,o+=V(r[l],e+1),c<n.length-1&&(o+='<span class="json-punctuation">,</span>'),o+=`
`}),o+=`</div>${t}<span class="json-punctuation">}</span>`,o}return String(r)}class Rt{constructor(){g(this,"logContainer",null);g(this,"logs",[]);g(this,"maxLogs",50);this.createLogContainer()}createLogContainer(){var t,s;const e=document.createElement("div");e.id="connection-log",e.style.cssText=`
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
      `,t.addEventListener("click",()=>this.toggle()),e.appendChild(t)}}log(e,t="info"){const s=new Date().toLocaleTimeString(),n={info:"var(--text-secondary)",success:"var(--success-color)",error:"var(--danger-color)",warning:"var(--warning-color)"}[t],a=`[${s}] ${e}`;this.logs.push(a),this.logs.length>this.maxLogs&&this.logs.shift();const i=document.getElementById("log-content");if(i){const o=document.createElement("div");o.style.color=n,o.textContent=a,i.appendChild(o),i.scrollTop=i.scrollHeight}console.log(`[ConnectionLog] ${a}`)}clear(){this.logs=[];const e=document.getElementById("log-content");e&&(e.innerHTML="")}show(){this.logContainer&&(this.logContainer.style.display="flex")}hide(){this.logContainer&&(this.logContainer.style.display="none")}toggle(){this.logContainer&&(this.logContainer.style.display==="flex"?this.hide():this.show())}}const b=new Rt;class zt{constructor(){g(this,"container",null);g(this,"intervalId",null);g(this,"lastFetchTime",null)}render(e){this.container=e,this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">System Health</h2>
          <button class="btn btn-primary" id="refresh-health" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="health-content" class="loading">Loading health status...</div>
      </div>
    `;const t=this.container.querySelector("#refresh-health");t==null||t.addEventListener("click",()=>this.manualRefresh()),b.log("Health Monitor initialized","info"),this.fetchHealthWithTimeout(),this.intervalId=setInterval(()=>this.fetchHealthWithTimeout(),1e4)}manualRefresh(){b.log("Manual refresh triggered","info"),x("Refreshing health status...","success"),this.fetchHealthWithTimeout()}stop(){this.intervalId&&(clearInterval(this.intervalId),this.intervalId=null)}async fetchHealthWithTimeout(){var t,s;const e=Date.now();b.log("Fetching health status from /api/admin/health...","info");try{const n=new Promise((l,c)=>setTimeout(()=>c(new Error("Request timeout after 5s")),5e3)),a=C.getHealth(),i=await Promise.race([a,n]),o=Date.now()-e;b.log(`Health status received in ${o}ms`,"success"),this.lastFetchTime=new Date,this.displayHealth(i)}catch(n){const a=Date.now()-e,i=n instanceof Error?n.message:"Unknown error";b.log(`Health fetch failed after ${a}ms: ${i}`,"error"),console.error("Failed to fetch health:",n);const o=(t=this.container)==null?void 0:t.querySelector("#health-content");o&&(o.innerHTML=`
          <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
            <div style="font-weight: 600; font-size: 1.125rem;">Failed to connect to API</div>
            <div style="color: var(--text-secondary); margin-top: 0.5rem; margin-bottom: 1rem;">
              Make sure the Vapor server is running on port 8080<br/>
              Error: ${i}
            </div>
            <button class="btn btn-primary" id="retry-health">🔄 Retry</button>
          </div>
        `,(s=o.querySelector("#retry-health"))==null||s.addEventListener("click",()=>this.manualRefresh())),x("Failed to fetch health status","error")}}displayHealth(e){var l;const t=(l=this.container)==null?void 0:l.querySelector("#health-content");if(!t)return;const s=e.status==="healthy",n=this.lastFetchTime?X(this.lastFetchTime.toISOString()):"just now";t.innerHTML=`
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
            ${e.jobs.map(c=>{const d=["ESPNTeamFetchJob","ScheduleUpdateJob","ESPNFetchJob"].includes(c.name);return`
              <tr>
                <td>${c.name}</td>
                <td>${c.schedule}</td>
                <td>${X(c.lastRun)}</td>
                <td><span class="badge ${c.status==="active"?"success":"warning"}">${c.status}</span></td>
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
        <span>Server time: ${X(e.timestamp)}</span>
      </div>
    `;const a=t.querySelector("#force-refresh");a==null||a.addEventListener("click",()=>this.forceRefresh(a));const i=t.querySelector("#refresh-schedules");i==null||i.addEventListener("click",()=>this.refreshSchedules());const o=t.querySelector("#clear-cache");o==null||o.addEventListener("click",()=>this.clearCache()),t.querySelectorAll(".trigger-job-btn").forEach(c=>{c.addEventListener("click",d=>{const h=d.target.dataset.job;h&&this.triggerJob(h,d.target)})})}async forceRefresh(e){const t=e.textContent;e.disabled=!0,e.textContent="Refreshing...";try{const s=await C.forceRefresh(),n=Object.entries(s.gamesLoaded).filter(([,a])=>a>0).map(([a,i])=>`${a}: ${i}`).join(", ");x(`${s.message}${n?` (${n})`:""}`,"success"),this.fetchHealthWithTimeout()}catch{x("Failed to force refresh schedules","error")}finally{e.disabled=!1,e.textContent=t}}async refreshSchedules(){try{const e=await C.refreshSchedules();x(e.message,"success"),this.fetchHealthWithTimeout()}catch{x("Failed to refresh schedules","error")}}async triggerJob(e,t){const s=t.textContent;t.disabled=!0,t.textContent="Running...";try{const n=await C.triggerJob(e);x(n.message,n.success?"success":"error"),this.fetchHealthWithTimeout()}catch{x(`Failed to trigger ${e}`,"error")}finally{t.disabled=!1,t.textContent=s}}async clearCache(){if(confirm("Are you sure you want to clear ALL cache? This will delete all Redis keys."))try{const e=await C.clearAllCache();x(e.message,"success"),this.fetchHealthWithTimeout()}catch{x("Failed to clear cache","error")}}}class Ot{constructor(){g(this,"container",null);g(this,"wsManager");g(this,"connectionStatus",null);g(this,"useWebSocket",!0);g(this,"refreshInterval",null);this.wsManager=new ve,this.connectionStatus=document.getElementById("connection-status")}render(e){var t,s;this.container=e,b.log("Live Games initialized","info"),this.container.innerHTML=`
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
    `,(t=this.container.querySelector("#refresh-live"))==null||t.addEventListener("click",()=>this.manualRefresh()),(s=this.container.querySelector("#toggle-mode"))==null||s.addEventListener("click",()=>this.toggleMode()),this.fetchLiveGames(),this.refreshInterval=setInterval(()=>this.fetchLiveGames(),1e4)}toggleMode(){this.useWebSocket=!this.useWebSocket,this.useWebSocket?(b.log("Switching to WebSocket mode","info"),x("Using WebSocket for live updates","success"),this.refreshInterval&&(clearInterval(this.refreshInterval),this.refreshInterval=null),this.wsManager.connect(e=>this.handleLiveData(e),e=>this.updateConnectionStatus(e))):(b.log("Switching to polling mode","info"),x("Using API polling (10s refresh)","success"),this.wsManager.disconnect(),this.refreshInterval||(this.refreshInterval=setInterval(()=>this.fetchLiveGames(),1e4)),this.fetchLiveGames())}async manualRefresh(){b.log("Manual refresh triggered","info"),x("Refreshing live games...","success"),await this.fetchLiveGames()}async fetchLiveGames(){var t,s;b.log("Fetching live games from /api/admin/live-espn...","info");const e=Date.now();try{const n=new Promise((d,h)=>setTimeout(()=>h(new Error("Request timed out after 10s")),1e4)),a=fetch("/api/admin/live-espn").then(async d=>{if(!d.ok)throw new Error(`HTTP ${d.status}`);return d.json()}),i=await Promise.race([a,n]),o=Date.now()-e;b.log(`All games fetched in ${o}ms`,"success");const l=(d=[])=>d.filter(h=>{const u=h.strStatus||"";return u==="in"||/^(Q[1-4]|OT|Half|P[1-3])/.test(u)}),c={nba:i.nba?{events:l(i.nba.events)}:void 0,nfl:i.nfl?{events:l(i.nfl.events)}:void 0,nhl:i.nhl?{events:l(i.nhl.events)}:void 0,mlb:i.mlb?{events:l(i.mlb.events)}:void 0,soccer:i.soccer?{events:l(i.soccer.events)}:void 0,golf:i.golf?{events:l(i.golf.events)}:void 0,tennis:i.tennis?{events:l(i.tennis.events)}:void 0,racing:i.racing?{events:l(i.racing.events)}:void 0};this.handleLiveData(c,i)}catch(n){const a=Date.now()-e,i=n instanceof Error?n.message:"Unknown error";b.log(`Failed to fetch live games after ${a}ms: ${i}`,"error");const o=(t=this.container)==null?void 0:t.querySelector("#live-games-content");o&&(o.innerHTML=`
          <div style="text-align: center; padding: 3rem;">
            <div style="font-size: 2rem; margin-bottom: 1rem; color: var(--danger-color);">Failed to load</div>
            <div style="color: var(--text-secondary); margin-bottom: 1rem;">${i}</div>
            <button class="btn btn-primary" id="retry-live">Retry</button>
          </div>
        `,(s=o.querySelector("#retry-live"))==null||s.addEventListener("click",()=>this.manualRefresh()))}}stop(){this.wsManager.disconnect(),this.updateConnectionStatus(!1),this.refreshInterval&&(clearInterval(this.refreshInterval),this.refreshInterval=null)}updateConnectionStatus(e){var s;this.connectionStatus&&(this.connectionStatus.className=`status-indicator ${e?"connected":"disconnected"}`);const t=(s=this.container)==null?void 0:s.querySelector("#ws-status");t&&(t.className=e?"badge success":"badge warning",t.textContent=e?"Connected":"Disconnected")}handleLiveData(e,t){var l,c;if(!this.container)return;const s=[{name:"NBA",data:e.nba,allData:t==null?void 0:t.nba,color:"#1d428a"},{name:"NFL",data:e.nfl,allData:t==null?void 0:t.nfl,color:"#013369"},{name:"NHL",data:e.nhl,allData:t==null?void 0:t.nhl,color:"#000000"},{name:"MLB",data:e.mlb,allData:t==null?void 0:t.mlb,color:"#002d72"},{name:"Soccer",data:e.soccer,allData:t==null?void 0:t.soccer,color:"#00a650"},{name:"Golf",data:e.golf,allData:t==null?void 0:t.golf,color:"#2ca58d"},{name:"Tennis",data:e.tennis,allData:t==null?void 0:t.tennis,color:"#c8b900"},{name:"Formula 1",data:e.racing,allData:t==null?void 0:t.racing,color:"#e10600"}],n=s.reduce((d,h)=>{var u,f;return d+(((f=(u=h.data)==null?void 0:u.events)==null?void 0:f.length)||0)},0),a=s.reduce((d,h)=>{var u,f;return d+(((f=(u=h.allData)==null?void 0:u.events)==null?void 0:f.length)||0)},0);b.log(`Displaying ${n} live games (${a} total from ESPN)`,n>0?"success":"info");const i=(l=this.container)==null?void 0:l.querySelector("#live-games-content"),o=(c=this.container)==null?void 0:c.querySelector("#ws-status");if(o&&(o.className=`badge ${n>0?"success":"info"}`,o.textContent=`${n} Live${a>0?` / ${a} Total`:""}`),i){const d=s.filter(u=>{var f,m,p,T;return(((m=(f=u.allData)==null?void 0:f.events)==null?void 0:m.length)||0)>0||(((T=(p=u.data)==null?void 0:p.events)==null?void 0:T.length)||0)>0}).map(u=>{var p,T,P,M;const f=((T=(p=u.data)==null?void 0:p.events)==null?void 0:T.length)||0,m=((M=(P=u.allData)==null?void 0:P.events)==null?void 0:M.length)||0;return`<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.5rem 0; border-bottom: 1px solid var(--border-color);">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 4px; height: 24px; background: ${u.color}; border-radius: 2px;"></span>
              <span style="font-weight: 500;">${u.name}</span>
            </div>
            <div style="display: flex; gap: 0.5rem;">
              ${f>0?`<span class="badge success">${f} Live</span>`:""}
              <span class="badge info">${m} Games</span>
            </div>
          </div>`}).join(""),h=n>0?s.map(u=>this.renderSportSection(u.name,u.data,u.color)).join(""):"";i.innerHTML=`
        ${d?`
          <div style="margin-bottom: 1.5rem;">
            <h3 style="font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem; color: var(--text-secondary);">ESPN Scoreboard Summary</h3>
            ${d}
          </div>
        `:""}

        ${h||`
          <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
            <div style="font-weight: 600; margin-bottom: 0.5rem;">No live games at the moment</div>
            <div style="font-size: 0.875rem;">Auto-refreshing every 10 seconds</div>
          </div>
        `}
      `,i.querySelectorAll("[data-tournament-id]").forEach(u=>{u.addEventListener("click",f=>{if(f.target.closest("button, a"))return;const m=u.querySelector(".tournament-collapsed"),p=u.querySelector(".tournament-expanded");m&&p&&(m.classList.toggle("hidden"),p.classList.toggle("hidden"))})})}}renderSportSection(e,t,s){return!t||!t.events||t.events.length===0?"":`
      <div class="card">
        <div class="card-header" style="border-left: 4px solid ${s};">
          <h3 class="card-title">${e}</h3>
          <span class="badge info">${t.events.length} Games</span>
        </div>
        <div style="display: grid; gap: 1rem;">
          ${t.events.map(n=>this.renderGame(n,e)).join("")}
        </div>
      </div>
    `}renderGame(e,t){return t==="Golf"||t==="Tennis"||t==="Formula 1"?this.renderTournamentGame(e):this.renderTeamGame(e)}renderTeamGame(e){const t=H(e.strStatus),s=e.intHomeScore||"0",n=e.intAwayScore||"0";return`
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span class="${t.class}">${t.text}</span>
          <span style="font-size: 0.875rem; color: var(--text-secondary);">${e.strProgress||""}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${e.strHomeTeamBadge?`<img src="${e.strHomeTeamBadge}" alt="${e.strHomeTeam}" style="width: 24px; height: 24px;">`:""}
            <span style="font-weight: 500;">${e.strHomeTeam}</span>
          </div>
          <span style="font-size: 1.25rem; font-weight: 700;">${s}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${e.strAwayTeamBadge?`<img src="${e.strAwayTeamBadge}" alt="${e.strAwayTeam}" style="width: 24px; height: 24px;">`:""}
            <span style="font-weight: 500;">${e.strAwayTeam}</span>
          </div>
          <span style="font-size: 1.25rem; font-weight: 700;">${n}</span>
        </div>
      </div>
    `}renderTournamentGame(e){const t=H(e.strStatus),s=e.idEvent||Math.random().toString(36).slice(2),n=(e.lastPlay||"").split(`
`).filter(h=>h.includes("|")).map((h,u)=>{const f=h.split("|"),m=f[0]||"TBD",p=f[1]||"--",T=f[2]?f[2].split(","):[];return{position:u+1,name:m,score:p,rounds:T}}),a=n.some(h=>h.rounds.length>0),i=Math.max(0,...n.map(h=>h.rounds.length)),o=n.length>0?n.slice(0,5).map(h=>`
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0; ${h.position===1?"font-weight: 600;":"color: var(--text-secondary);"}">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${h.position}</span>
              <span>${h.name}</span>
            </div>
            <span style="font-weight: 500;">${h.score}</span>
          </div>
        `).join(""):`<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0;">
            <span>${e.strAwayTeam}</span>
            <span style="font-weight: 600;">${e.intAwayScore||"--"}</span>
         </div>`,l=a?Array.from({length:i},(h,u)=>`<span style="width: 2.5rem; text-align: right; font-size: 0.75rem;">R${u+1}</span>`).join(""):"",c=n.map(h=>{const u=a?Array.from({length:i},(f,m)=>`<span style="width: 2.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${h.rounds[m]||"-"}</span>`).join(""):"";return`
        <div style="display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0; ${h.position===1?"font-weight: 600;":"color: var(--text-secondary);"}">
          <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${h.position}</span>
          <span style="flex: 1;">${h.name}</span>
          <span style="width: 3rem; text-align: right; font-weight: 500;">${h.score}</span>
          ${u}
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
    `}}var y=(r=>(r[r.English_Premier_League=4328]="English_Premier_League",r[r.English_League_Championship=4329]="English_League_Championship",r[r.German_Bundesliga=4331]="German_Bundesliga",r[r.Serie_A=4332]="Serie_A",r[r.Ligue_1=4334]="Ligue_1",r[r.La_Liga=4335]="La_Liga",r[r.Eredivisie=4337]="Eredivisie",r[r.MLS=4346]="MLS",r[r.Liga_MX=4350]="Liga_MX",r[r.FIFA_World_Cup=4429]="FIFA_World_Cup",r[r.UEFA_Champions_League=4480]="UEFA_Champions_League",r[r.UEFA_Europa_League=4481]="UEFA_Europa_League",r[r.FA_Cup=4482]="FA_Cup",r[r.Copa_del_Rey=4483]="Copa_del_Rey",r[r.Coupe_De_France=4484]="Coupe_De_France",r[r.DFB_Pokal=4485]="DFB_Pokal",r[r.UEFA_Nations_League=4490]="UEFA_Nations_League",r[r.Copa_America=4499]="Copa_America",r[r.UEFA_Conference_League=5071]="UEFA_Conference_League",r[r.Womens_World_Cup=4565]="Womens_World_Cup",r[r.NFL=4391]="NFL",r[r.NBA=4387]="NBA",r[r.NHL=4380]="NHL",r[r.MLB=4424]="MLB",r[r.PGA=4425]="PGA",r[r.ATP=4464]="ATP",r[r.WTA=4517]="WTA",r[r.Formula1=4370]="Formula1",r))(y||{});const j={4328:"English Premier League",4329:"English Championship",4331:"Bundesliga",4332:"Serie A",4334:"Ligue 1",4335:"La Liga",4337:"Eredivisie",4346:"MLS",4350:"Liga MX",4429:"FIFA World Cup",4480:"UEFA Champions League",4481:"UEFA Europa League",4482:"FA Cup",4483:"Copa Del Rey",4484:"Coupe De France",4485:"DFB Pokal",4490:"UEFA Nations League",4499:"Copa America",5071:"UEFA Conference League",4391:"NFL",4424:"MLB",4380:"NHL",4387:"NBA",4565:"FIFA Women's World Cup",4425:"PGA Tour",4464:"ATP Tour",4517:"WTA Tour",4370:"Formula 1"};class Wt{constructor(){g(this,"container",null);g(this,"leagueStats",new Map);g(this,"scheduleData",null);g(this,"currentFilter","all");g(this,"selectedLeague",null);g(this,"isLoading",!1);g(this,"selectedSeason","all");g(this,"selectedTeam","all");g(this,"expandedRaceSessions",new Set)}async render(e){this.container=e,b.log("League Explorer initialized","info"),this.showLoadingState(),await this.loadData()}showLoadingState(){this.container&&(this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
        </div>
        <div style="text-align: center; padding: 3rem; color: var(--text-secondary);">
          <div style="font-size: 2rem; margin-bottom: 1rem; animation: pulse 1.5s infinite;">Loading schedules...</div>
          <div style="font-size: 0.875rem;">Fetching data from server</div>
        </div>
      </div>
    `)}async loadData(){if(!this.isLoading){this.isLoading=!0,b.log("Fetching schedules from /v2025/schedules...","info");try{const e=Date.now(),t=new Promise((n,a)=>setTimeout(()=>a(new Error("Request timed out after 15s")),15e3));this.scheduleData=await Promise.race([C.getSchedules(),t]);const s=Date.now()-e;b.log(`Schedules loaded in ${s}ms`,"success"),this.computeAllStats(),this.displayAllLeagues()}catch(e){const t=e instanceof Error?e.message:"Unknown error";b.log(`Failed to fetch schedules: ${t}`,"error"),this.showErrorState(t)}finally{this.isLoading=!1}}}showErrorState(e){var t;this.container&&(this.container.innerHTML=`
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
    `,(t=this.container.querySelector("#retry-btn"))==null||t.addEventListener("click",()=>{this.showLoadingState(),this.loadData()}))}stop(){}computeAllStats(){if(this.leagueStats.clear(),!this.scheduleData)return;const e=(s,n)=>{const a=new Set,i=this.isIndividualSport(n);let o=0,l=0,c=0;for(const d of s){if(i){if(d.strHomeTeam&&d.strHomeTeam!=="TBD"){const u=n===y.Formula1?this.extractGPName(d.strHomeTeam):d.strHomeTeam;a.add(u)}}else d.strHomeTeam&&a.add(d.strHomeTeam),d.strAwayTeam&&a.add(d.strAwayTeam);const h=(d.strStatus||"").toLowerCase();["ft","aot","final","final/ot","post","completed","finished","match finished","ap"].includes(h)?l++:["ns","pre","","scheduled","not started"].includes(h)?c++:o++}this.leagueStats.set(n,{league:j[n]||"Unknown",leagueId:n,sport:this.getSportForLeague(n),totalGames:s.length,liveGames:o,completedGames:l,upcomingGames:c,teams:Array.from(a).sort()})};this.scheduleData.nba&&e(this.scheduleData.nba.events,y.NBA),this.scheduleData.nfl&&e(this.scheduleData.nfl.events,y.NFL),this.scheduleData.nhl&&e(this.scheduleData.nhl.events,y.NHL),this.scheduleData.mlb&&e(this.scheduleData.mlb.events,y.MLB),this.scheduleData.golf&&e(this.scheduleData.golf.events,y.PGA),this.scheduleData.racing&&e(this.scheduleData.racing.events,y.Formula1);const t=s=>{const n=new Map;for(const a of s){const i=parseInt(a.idLeague||"0");if(!i)continue;const o=n.get(i)||[];o.push(a),n.set(i,o)}return n};if(this.scheduleData.soccer){const s=t(this.scheduleData.soccer.events);for(const[n,a]of s){const i=n;j[i]&&e(a,i)}}if(this.scheduleData.tennis){const s=t(this.scheduleData.tennis.events);for(const[n,a]of s){const i=n;j[i]&&e(a,i)}}b.log(`Computed stats for ${this.leagueStats.size} leagues`,"success")}displayAllLeagues(){var s,n,a;if(!this.container)return;const e=this.leagueStats.size,t=Array.from(this.leagueStats.values()).reduce((i,o)=>i+o.totalGames,0);this.container.innerHTML=`
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
    `,(s=this.container.querySelector("#refresh-leagues"))==null||s.addEventListener("click",()=>{x("Refreshing leagues...","success"),this.leagueStats.clear(),this.showLoadingState(),this.loadData()}),this.selectedLeague?((n=this.container.querySelector("#back-to-leagues"))==null||n.addEventListener("click",()=>{this.selectedLeague=null,this.selectedSeason="all",this.selectedTeam="all",this.expandedRaceSessions.clear(),this.displayAllLeagues()}),this.container.querySelectorAll("[data-season]").forEach(i=>{i.addEventListener("click",o=>{this.selectedSeason=o.target.dataset.season||"all",this.displayAllLeagues()})}),this.container.querySelectorAll("[data-team]").forEach(i=>{i.addEventListener("click",o=>{this.selectedTeam=o.target.dataset.team||"all",this.displayAllLeagues()})}),(a=this.container.querySelector("#clear-filters"))==null||a.addEventListener("click",()=>{this.selectedSeason="all",this.selectedTeam="all",this.displayAllLeagues()}),this.container.querySelectorAll("[data-racing-session-id]").forEach(i=>{i.addEventListener("click",()=>{const o=i.dataset.racingSessionId;o&&(this.expandedRaceSessions.has(o)?this.expandedRaceSessions.delete(o):this.expandedRaceSessions.add(o),this.displayAllLeagues())})})):(this.container.querySelectorAll(".filter-btn").forEach(i=>{i.addEventListener("click",o=>{const l=o.target.dataset.sport;l&&(this.currentFilter=l,this.displayAllLeagues())})}),this.container.querySelectorAll("[data-league-id]").forEach(i=>{i.addEventListener("click",()=>{const o=i.dataset.leagueId;o&&(this.selectedLeague=parseInt(o),this.selectedSeason="all",this.selectedTeam="all",this.expandedRaceSessions.clear(),this.displayAllLeagues())})}))}renderLeagueGrid(){return`
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
      `}).join("")}getSportForLeague(e){switch(e){case y.NBA:return"basketball";case y.NFL:return"football";case y.NHL:return"hockey";case y.MLB:return"baseball";case y.PGA:return"golf";case y.ATP:case y.WTA:return"tennis";case y.Formula1:return"racing";default:return"soccer"}}isIndividualSport(e){return e===y.PGA||e===y.ATP||e===y.WTA||e===y.Formula1}isIndividualSportGame(e){const t=parseInt(e.idLeague||"0");return t===y.PGA||t===y.ATP||t===y.WTA||t===y.Formula1}isRacingLeague(e){return e===y.Formula1}extractGPName(e){return e.replace(/\s+(Sprint Shootout|Sprint|FP1|FP2|FP3|Qual|Race)$/i,"").trim()}getSessionOrder(e){const t=e.toLowerCase();return t.endsWith(" fp1")?0:t.endsWith(" fp2")?1:t.endsWith(" fp3")?2:t.endsWith(" sprint shootout")?3:t.endsWith(" sprint")?4:t.endsWith(" qual")?5:t.endsWith(" race")?6:7}getSessionLabel(e){const t=e.toLowerCase();return t.endsWith(" fp1")?"Free Practice 1":t.endsWith(" fp2")?"Free Practice 2":t.endsWith(" fp3")?"Free Practice 3":t.endsWith(" sprint shootout")?"Sprint Shootout":t.endsWith(" sprint")?"Sprint":t.endsWith(" qual")?"Qualifying":t.endsWith(" race")?"Race":e}groupRacingGamesByGP(e){const t=new Map;for(const s of e){const n=this.extractGPName(s.strHomeTeam||"");if(!n)continue;const a=t.get(n)||[];a.push(s),t.set(n,a)}for(const[,s]of t)s.sort((n,a)=>this.getSessionOrder(n.strHomeTeam||"")-this.getSessionOrder(a.strHomeTeam||""));return t}getSportColor(e){switch(e){case"basketball":return"#1d428a";case"football":return"#013369";case"hockey":return"#000000";case"baseball":return"#002d72";case"soccer":return"#00a650";case"golf":return"#2ca58d";case"tennis":return"#c8b900";case"racing":return"#e10600";default:return"var(--primary-color)"}}capitalizeFirst(e){return e.charAt(0).toUpperCase()+e.slice(1)}getGamesForLeague(e){return this.scheduleData?e===y.NBA&&this.scheduleData.nba?this.scheduleData.nba.events:e===y.NFL&&this.scheduleData.nfl?this.scheduleData.nfl.events:e===y.NHL&&this.scheduleData.nhl?this.scheduleData.nhl.events:e===y.MLB&&this.scheduleData.mlb?this.scheduleData.mlb.events:e===y.PGA&&this.scheduleData.golf?this.scheduleData.golf.events:e===y.Formula1&&this.scheduleData.racing?this.scheduleData.racing.events:(e===y.ATP||e===y.WTA)&&this.scheduleData.tennis?this.scheduleData.tennis.events.filter(t=>t.idLeague===String(e)):this.scheduleData.soccer?this.scheduleData.soccer.events.filter(t=>t.idLeague===String(e)):[]:[]}renderLeagueDetail(e){const t=this.leagueStats.get(e),s=j[e]||"Unknown League",n=e;if(!t||!this.scheduleData)return'<div style="text-align: center; padding: 3rem; color: var(--text-secondary);">No data available for this league</div>';const a=this.getGamesForLeague(e),i=this.extractSeasons(a),o=this.extractTeams(a),l=this.isIndividualSport(n),c=this.isRacingLeague(e);let d=a;this.selectedSeason!=="all"&&(d=d.filter(v=>this.getGameSeason(v)===this.selectedSeason)),this.selectedTeam!=="all"&&(d=d.filter(v=>c?this.extractGPName(v.strHomeTeam||"")===this.selectedTeam:l?v.strHomeTeam===this.selectedTeam:v.strHomeTeam===this.selectedTeam||v.strAwayTeam===this.selectedTeam));const h=["ft","aot","final","final/ot","post","ap","completed","finished","match finished"],u=["ns","pre","","scheduled","not started"],f=d.filter(v=>{const E=(v.strStatus||"").toLowerCase();return!h.includes(E)&&!u.includes(E)}),m=d.filter(v=>{const E=(v.strStatus||"").toLowerCase();return u.includes(E)}).sort((v,E)=>{const U=new Date(v.isoDate||v.strTimestamp||0).getTime(),Q=new Date(E.isoDate||E.strTimestamp||0).getTime();return U-Q}),p=d.filter(v=>{const E=(v.strStatus||"").toLowerCase();return h.includes(E)}).sort((v,E)=>{const U=new Date(v.isoDate||v.strTimestamp||0).getTime();return new Date(E.isoDate||E.strTimestamp||0).getTime()-U}),T=this.getSportForLeague(n),P=this.getSportColor(T),M=this.selectedSeason!=="all"||this.selectedTeam!=="all",S=c?this.groupRacingGamesByGP(f):null,k=c?this.groupRacingGamesByGP(m):null,L=c?this.groupRacingGamesByGP(p):null,z=c?"Grand Prix":l?"Tournament":"Team",J=c?"Grand Prix":l?"Tournaments":"Teams",me=c?"sessions":l?"events":"games";return`
      <div style="border-left: 4px solid ${P}; padding-left: 1rem; margin-bottom: 1.5rem;">
        <h2 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 0.25rem;">${s}</h2>
        <div style="color: var(--text-secondary); font-size: 0.875rem;">${this.capitalizeFirst(T)} &middot; ${a.length} total ${me} &middot; ${t.teams.length} ${J}</div>
      </div>

      <!-- Filter Controls -->
      <div style="margin-bottom: 1.5rem;">
        ${i.length>1?`
          <div style="margin-bottom: 1rem;">
            <label style="display: block; font-size: 0.875rem; font-weight: 600; margin-bottom: 0.5rem;">Season</label>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <button class="filter-btn ${this.selectedSeason==="all"?"active":""}" data-season="all">All Seasons</button>
              ${i.map(v=>`
                <button class="filter-btn ${this.selectedSeason===v?"active":""}" data-season="${v}">${v}</button>
              `).join("")}
            </div>
          </div>
        `:""}

        ${o.length>1&&o.length<=40?`
          <div>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
              <label style="font-size: 0.875rem; font-weight: 600;">${z}</label>
              ${M?'<button class="btn btn-secondary" id="clear-filters" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear Filters</button>':""}
            </div>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <button class="filter-btn ${this.selectedTeam==="all"?"active":""}" data-team="all">All ${J}</button>
              ${o.map(v=>`
                <button class="filter-btn ${this.selectedTeam===v?"active":""}" data-team="${v}">${v}</button>
              `).join("")}
            </div>
          </div>
        `:M?'<button class="btn btn-secondary" id="clear-filters" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear Filters</button>':""}
      </div>

      <div class="grid grid-3" style="margin-bottom: 1.5rem;">
        <div class="stat-card">
          <div class="stat-value">${d.length}</div>
          <div class="stat-label">Games${M?" (Filtered)":""}</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" style="color: var(--success-color);">${f.length}</div>
          <div class="stat-label">Live</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" style="color: var(--warning-color);">${m.length}</div>
          <div class="stat-label">Upcoming</div>
        </div>
      </div>

      ${f.length>0?`
        <div class="card" style="margin-bottom: 1.5rem; border-left: 4px solid var(--success-color);">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem; display: flex; align-items: center; gap: 0.5rem;">
            <span class="badge success">Live</span>
            ${c&&S?`${S.size} Grand Prix In Progress (${f.length} sessions)`:`${f.length} Games In Progress`}
          </h3>
          <div style="display: grid; gap: 1rem;">
            ${c&&S?Array.from(S.entries()).map(([v,E])=>this.renderRacingGPGroup(v,E,"live")).join(""):f.map(v=>l?this.renderTournamentCard(v):this.renderGameCard(v)).join("")}
          </div>
        </div>
      `:""}

      ${m.length>0?`
        <div class="card" style="margin-bottom: 1.5rem;">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
            ${c&&k?`Upcoming Grand Prix (${k.size} GPs, ${m.length} sessions)`:`Upcoming ${l?"Events":"Games"} (${m.length})`}
          </h3>
          ${c&&k?`
            <div>
              ${Array.from(k.entries()).map(([v,E])=>this.renderRacingGPGroup(v,E,"upcoming")).join("")}
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
                ${m.slice(0,25).map(v=>l?this.renderTournamentRow(v):this.renderGameRow(v)).join("")}
              </tbody>
            </table>
            ${m.length>25?`<div style="text-align: center; margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">Showing 25 of ${m.length} upcoming ${l?"events":"games"}</div>`:""}
          `}
        </div>
      `:""}

      ${p.length>0?`
        <div class="card">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
            ${c&&L?`Completed Grand Prix (${L.size} GPs, ${p.length} sessions)`:`Completed ${l?"Events":"Games"} (${p.length})`}
          </h3>
          ${c&&L?`
            <div>
              ${Array.from(L.entries()).map(([v,E])=>this.renderRacingGPGroup(v,E,"completed")).join("")}
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
                ${p.slice(0,25).map(v=>l?this.renderTournamentRow(v):this.renderGameRow(v)).join("")}
              </tbody>
            </table>
            ${p.length>25?`<div style="text-align: center; margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">Showing 25 of ${p.length} completed ${l?"events":"games"}</div>`:""}
          `}
        </div>
      `:""}

      ${d.length===0?'<div style="text-align: center; padding: 3rem; color: var(--text-secondary);">No games found for this league</div>':""}
    `}renderGameCard(e){const t=H(e.strStatus),s=e.intHomeScore||"0",n=e.intAwayScore||"0";return`
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
    `}renderTournamentCard(e){const t=H(e.strStatus),s=(e.lastPlay||"").split(`
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
    `}renderGameRow(e){const t=H(e.strStatus),s=e.intHomeScore||"-",n=e.intAwayScore||"-";return`
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
        <td style="font-size: 0.875rem;">${e.strProgress||q(e.strTimestamp)}</td>
      </tr>
    `}renderTournamentRow(e){const t=H(e.strStatus),s=e.strAwayTeam!=="TBD"?e.strAwayTeam:"",n=e.intAwayScore||"-";return`
      <tr>
        <td>
          <span style="font-weight: 500;">${e.strHomeTeam}</span>
        </td>
        ${s?`<td>${s}</td><td>${n}</td>`:'<td colspan="2" style="color: var(--text-secondary);">-</td>'}
        <td><span class="${t.class}">${t.text}</span></td>
        <td style="font-size: 0.875rem;">${e.strProgress||q(e.strTimestamp)}</td>
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
    `}renderRacingGPGroup(e,t,s){const n=t.find(c=>(c.strHomeTeam||"").toLowerCase().endsWith(" race")),a=t[0],i=a?q(a.strTimestamp):"";let o="",l="";if(s==="completed"&&n){const c=(n.lastPlay||"").split(`
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
    `}renderRacingSessionRow(e,t){const s=this.getSessionLabel(e.strHomeTeam||""),n=H(e.strStatus),a=(e.strHomeTeam||"").toLowerCase().endsWith(" race"),i=this.expandedRaceSessions.has(e.idEvent||""),l=t==="completed"&&(e.lastPlay||"").includes("|");let c="",d="",h="";if(t==="completed"){const f=(e.lastPlay||"").split(`
`).filter(m=>m.includes("|"));if(f.length>0){const m=f[0].split("|");c=m[0]||"",h=m[1]||"",d=m[3]||""}else e.strAwayTeam&&e.strAwayTeam!=="TBD"&&(c=e.strAwayTeam)}const u=a?"rgba(225, 6, 0, 0.04)":"transparent";return`
      <div ${l?`data-racing-session-id="${e.idEvent}"`:""} style="padding: 0.5rem 1rem; border-bottom: 1px solid var(--border-color); background-color: ${u}; ${l?"cursor: pointer;":""} display: flex; flex-direction: column; transition: background-color 0.15s;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            ${l?`<span style="font-size: 0.7rem; color: var(--text-secondary); transition: transform 0.2s; transform: rotate(${i?"90":"0"}deg); display: inline-block;">&#9654;</span>`:'<span style="width: 0.7rem; display: inline-block;"></span>'}
            <span style="font-weight: ${a?"600":"500"}; font-size: 0.875rem;">${s}</span>
            ${c&&!i?`<span style="font-size: 0.8rem; color: var(--text-secondary);">${c}${d?` <span style="font-size: 0.75rem;">(${d})</span>`:""}${h?` <span style="font-size: 0.75rem; color: var(--text-secondary);">P${h}</span>`:""}</span>`:""}
          </div>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <span style="font-size: 0.8rem; color: var(--text-secondary);">${e.strProgress||q(e.strTimestamp)}</span>
            <span class="${n.class}" style="font-size: 0.7rem;">${n.text}</span>
          </div>
        </div>
        ${i?`<div style="padding: 0.5rem 0 0.25rem 2rem;">${this.renderRacingLeaderboard(e)}</div>`:""}
      </div>
    `}extractSeasons(e){const t=new Set;for(const s of e){const n=this.getGameSeason(s);n&&t.add(n)}return Array.from(t).sort().reverse()}extractTeams(e){var a;const t=new Set,s=parseInt(((a=e[0])==null?void 0:a.idLeague)||"0"),n=this.isRacingLeague(s);for(const i of e)if(n){const o=this.extractGPName(i.strHomeTeam||"");o&&t.add(o)}else this.isIndividualSportGame(i)?i.strHomeTeam&&i.strHomeTeam!=="TBD"&&t.add(i.strHomeTeam):(i.strHomeTeam&&t.add(i.strHomeTeam),i.strAwayTeam&&t.add(i.strAwayTeam));return Array.from(t).sort()}getGameSeason(e){const t=e.strTimestamp||e.isoDate;if(!t)return null;try{const s=new Date(t),n=s.getFullYear();return s.getMonth()+1>=8?`${n}-${n+1}`:`${n-1}-${n}`}catch{return null}}}class Gt{constructor(){g(this,"container",null)}async render(e){this.container=e,this.container.innerHTML='<div class="loading">Analyzing data gaps...</div>';try{const t=await C.getDataGaps();this.displayGaps(t)}catch(t){console.error("Failed to fetch data gaps:",t),x("Failed to analyze data gaps","error")}}stop(){}displayGaps(e){this.container&&(this.container.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Data Completeness Analysis</h2>
          <span class="badge ${e.summary.overallCompleteness>.95?"success":e.summary.overallCompleteness>.8?"warning":"danger"}">
            ${oe(e.summary.overallCompleteness)} Complete
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
        <td><span class="badge ${s}">${oe(t)}</span></td>
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
    `}}class Nt{constructor(){g(this,"container",null);g(this,"keys",[]);g(this,"filteredKeys",[])}async render(e){this.container=e,b.log("Redis Viewer initialized","info"),this.container.innerHTML='<div class="loading">Loading Redis keys...</div>',await this.loadKeys()}async loadKeys(){var t;b.log("Fetching Redis keys from /api/admin/redis/keys...","info");const e=Date.now();try{const s=await C.getRedisKeys(),n=Date.now()-e;b.log(`Loaded ${s.keys.length} Redis keys in ${n}ms`,"success"),this.keys=s.keys,this.filteredKeys=this.keys,this.displayKeys()}catch(s){const n=Date.now()-e;b.log(`Failed to fetch Redis keys after ${n}ms: ${s}`,"error"),console.error("Failed to fetch Redis keys:",s),x("Failed to fetch Redis keys","error"),this.container&&(this.container.innerHTML=`
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
    `;const e=this.container.querySelector("#refresh-redis");e==null||e.addEventListener("click",()=>{b.log("Manual refresh triggered","info"),x("Refreshing Redis keys...","success"),this.loadKeys()}),this.container.querySelector("#key-search").addEventListener("input",s=>{const n=s.target.value.toLowerCase();this.filteredKeys=this.keys.filter(a=>a.key.toLowerCase().includes(n)),this.updateKeysTable()}),this.setupActionListeners()}renderKeyRow(e,t){return`
      <tr>
        <td style="font-family: monospace; font-size: 0.875rem;">${this.escapeHtml(e.key)}</td>
        <td><span class="badge info">${e.type}</span></td>
        <td>${ae(e.size)}</td>
        <td>${ie(e.ttl)}</td>
        <td style="white-space: nowrap;">
          <button class="btn btn-secondary btn-view" data-index="${t}" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; min-width: 70px;">View</button>
          <button class="btn btn-danger btn-delete" data-index="${t}" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; margin-left: 0.25rem;">Delete</button>
        </td>
      </tr>
    `}escapeHtml(e){const t=document.createElement("div");return t.textContent=e,t.innerHTML}updateKeysTable(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#keys-table-body");e&&(e.innerHTML=this.filteredKeys.map((s,n)=>this.renderKeyRow(s,n)).join(""))}setupActionListeners(){var s;const e=(s=this.container)==null?void 0:s.querySelector("#keys-table");if(!e){b.log("Keys table not found, cannot setup listeners","error");return}const t=n=>{const a=n.target;if(a.classList.contains("btn-view")){n.preventDefault(),n.stopPropagation();const i=parseInt(a.dataset.index||"-1");if(b.log(`View button clicked, index: ${i}, filteredKeys length: ${this.filteredKeys.length}`,"info"),i>=0&&i<this.filteredKeys.length){const o=this.filteredKeys[i].key;b.log(`Viewing key: ${o}`,"info");const l=a;l.disabled=!0,l.textContent="Loading...",this.viewKey(o).finally(()=>{l.disabled=!1,l.textContent="View"})}else b.log(`Invalid index: ${i}`,"error")}else if(a.classList.contains("btn-delete")){n.preventDefault(),n.stopPropagation();const i=parseInt(a.dataset.index||"-1");if(i>=0&&i<this.filteredKeys.length){const o=this.filteredKeys[i].key;this.deleteKey(o)}}};e.addEventListener("click",t),b.log(`Event delegation set up for ${this.filteredKeys.length} keys`,"info")}async viewKey(e){var s,n,a,i;b.log(`Viewing Redis key: ${e}`,"info");const t=(s=this.container)==null?void 0:s.querySelector("#key-detail");if(!t){b.log("Detail div not found","error");return}t.innerHTML=`
      <div class="card">
        <div class="card-header">
          <h3 class="card-title" style="font-family: monospace; font-size: 1rem; word-break: break-all;">${this.escapeHtml(e)}</h3>
        </div>
        <div style="text-align: center; padding: 3rem;">
          <div class="loading">Loading key value...</div>
        </div>
      </div>
    `,t.style.display="block";try{const o=Date.now(),l=await C.getRedisKey(e),c=Date.now()-o;b.log(`Key content loaded (${l.value.length} bytes) in ${c}ms`,"success");const d=Ht(l.value);t.innerHTML=`
        <div class="card">
          <div class="card-header">
            <h3 class="card-title" style="font-family: monospace; font-size: 1rem; word-break: break-all;">${this.escapeHtml(e)}</h3>
            <div style="display: flex; gap: 0.5rem;">
              <span class="badge info">${l.type}</span>
              ${l.ttl?`<span class="badge warning">TTL: ${ie(l.ttl)}</span>`:""}
              <span class="badge info">${ae(l.value.length)}</span>
            </div>
          </div>
          <div class="json-viewer"><pre style="margin: 0;">${d}</pre></div>
          <div style="margin-top: 1rem; display: flex; gap: 0.5rem;">
            <button class="btn btn-secondary" id="copy-json">📋 Copy</button>
            <button class="btn btn-danger" id="close-detail">Close</button>
          </div>
        </div>
      `,(n=t.querySelector("#copy-json"))==null||n.addEventListener("click",()=>{navigator.clipboard.writeText(l.value),x("Copied to clipboard","success")}),(a=t.querySelector("#close-detail"))==null||a.addEventListener("click",()=>{t&&(t.style.display="none")}),this.setupJSONCollapseHandlers(t),t.scrollIntoView({behavior:"smooth",block:"nearest"})}catch(o){b.log(`Failed to fetch key content: ${o}`,"error"),console.error("Failed to fetch key content:",o),x("Failed to fetch key content","error"),t.innerHTML=`
        <div class="card">
          <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
            <div style="font-weight: 600; font-size: 1.125rem;">Failed to load key</div>
            <div style="margin-top: 0.5rem; font-size: 0.875rem; color: var(--text-secondary);">${o}</div>
            <button class="btn btn-danger" id="close-error" style="margin-top: 1rem;">Close</button>
          </div>
        </div>
      `,(i=t.querySelector("#close-error"))==null||i.addEventListener("click",()=>{t&&(t.style.display="none")})}}async deleteKey(e){if(confirm(`Are you sure you want to delete key "${e}"?`))try{const t=await C.invalidateKey(e);x(t.message,t.success?"success":"warning"),t.success&&(this.keys=this.keys.filter(s=>s.key!==e),this.filteredKeys=this.filteredKeys.filter(s=>s.key!==e),this.updateKeysTable())}catch(t){console.error("Failed to delete key:",t),x("Failed to delete key","error")}}setupJSONCollapseHandlers(e){const t=e.querySelectorAll(".json-collapse-btn");t.forEach(s=>{s.addEventListener("click",n=>{n.preventDefault();const a=n.target,i=a.dataset.target;if(i){const o=e.querySelector(`#${i}`);if(o){const l=o.classList.toggle("collapsed");a.classList.toggle("collapsed");const c=a.textContent||"";l?a.textContent=c.replace("▼","▶"):a.textContent=c.replace("▶","▼")}}})}),b.log(`Set up ${t.length} JSON collapse handlers`,"info")}}class It{constructor(){g(this,"container",null);g(this,"teams",[]);g(this,"filteredTeams",[])}async render(e){this.container=e,this.container.innerHTML='<div class="loading">Loading teams...</div>';try{this.teams=await C.getTeams(),this.filteredTeams=this.teams,this.displayTeams()}catch(t){console.error("Failed to fetch teams:",t),x("Failed to fetch teams","error")}}stop(){}displayTeams(){if(!this.container)return;const e=this.teams.filter(s=>!s.strTeamBadge).length;this.container.innerHTML=`
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
    `}updateTeamsGrid(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#teams-grid");e&&(e.innerHTML=this.filteredTeams.map(s=>this.renderTeamCard(s)).join(""))}}class qt{constructor(){g(this,"container",null);g(this,"intervalId",null)}render(e){var t,s,n,a;this.container=e,this.container.innerHTML=`
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
    `,(t=this.container.querySelector("#refresh-registrations"))==null||t.addEventListener("click",()=>this.fetchRegistrations()),(s=this.container.querySelector("#refresh-pipeline"))==null||s.addEventListener("click",()=>this.fetchDiagnostics()),(n=this.container.querySelector("#trigger-push-to-start"))==null||n.addEventListener("click",()=>{this.triggerPushToStart(this.container.querySelector("#trigger-push-to-start"))}),(a=this.container.querySelector("#trigger-all-push-to-start"))==null||a.addEventListener("click",()=>{this.triggerAllPushToStart(this.container.querySelector("#trigger-all-push-to-start"))}),this.fetchRegistrations(),this.fetchDiagnostics(),this.intervalId=setInterval(()=>{this.fetchRegistrations(),this.fetchDiagnostics()},1e4)}stop(){this.intervalId&&(clearInterval(this.intervalId),this.intervalId=null)}async fetchDiagnostics(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#pipeline-content");if(e)try{const s=await C.getPushToStartDiagnostics();let n=`
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
      `}}async fetchRegistrations(){var t;const e=(t=this.container)==null?void 0:t.querySelector("#registrations-content");if(e)try{const s=await C.getPushToStartRegistrations();if(s.totalTokens===0){e.innerHTML=`
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
        `}n+="</tbody></table>",e.innerHTML=n,e.querySelectorAll(".select-event-btn").forEach(a=>{a.addEventListener("click",i=>{var l;const o=i.target.dataset.eventId;if(o){const c=(l=this.container)==null?void 0:l.querySelector("#debug-event-id");c&&(c.value=o,c.focus(),x(`Selected: ${o}`,"success"))}})})}catch(s){const n=s instanceof Error?s.message:"Unknown error";e.innerHTML=`
        <div style="text-align: center; padding: 2rem; color: var(--danger-color);">
          <div style="font-size: 2rem; margin-bottom: 0.5rem;">⚠️</div>
          <div>Failed to load registrations: ${n}</div>
        </div>
      `}}async triggerAllPushToStart(e){var i,o,l,c,d,h,u,f;const t=e.textContent;e.disabled=!0,e.textContent="Starting all...";const s=(i=this.container)==null?void 0:i.querySelector("#debug-result"),n=((c=(l=(o=this.container)==null?void 0:o.querySelector("#debug-home-team"))==null?void 0:l.value)==null?void 0:c.trim())||"Debug Lions",a=((u=(h=(d=this.container)==null?void 0:d.querySelector("#debug-away-team"))==null?void 0:h.value)==null?void 0:u.trim())||"Debug Tigers";try{const m=await C.getPushToStartRegistrations(),p=new Set;for(const k of m.registrations)for(const L of k.eventIDs)p.add(L);if(p.size===0){x("No event IDs found in registrations","error");return}let T=0;const P=[],M=[],S=[];for(const k of p)try{const L=await C.triggerDebugPushToStart(k,n,a);T+=L.notified,P.push(`${k}: ${L.notified} device(s)${L.reason?` (${L.reason})`:""}`),L.trace&&M.push(`--- ${k} ---
${L.trace}`),(f=L.errors)!=null&&f.length&&S.push(...L.errors.map(z=>`${k}: ${z}`))}catch(L){const z=L instanceof Error?L.message:"Unknown error";P.push(`${k}: failed (${z})`)}s&&(s.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: ${T>0?"rgba(34,197,94,0.1)":"rgba(234,179,8,0.1)"};">
            <strong>${T>0?"✅":"⚠️"} Triggered ${p.size} event(s), notified ${T} device(s)</strong>
            <div style="margin-top: 0.5rem; font-family: monospace; font-size: 0.8rem; color: var(--text-secondary);">
              ${P.map(k=>`<div>${k}</div>`).join("")}
            </div>
            ${S.length?`<div style="margin-top: 0.5rem; color: var(--danger-color);"><strong>APNS Errors:</strong><pre style="margin: 0.25rem 0; font-size: 0.75rem; white-space: pre-wrap;">${S.join(`
`)}</pre></div>`:""}
            ${M.length?`<details style="margin-top: 0.75rem;"><summary style="cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);">Server Trace</summary><pre style="margin-top: 0.5rem; padding: 0.75rem; background: var(--bg-color); border: 1px solid var(--border-color); border-radius: 0.25rem; font-size: 0.7rem; white-space: pre-wrap; overflow-x: auto; color: var(--text-secondary);">${M.join(`

`)}</pre></details>`:""}
          </div>
        `),x(`Started all: ${T} device(s) notified across ${p.size} event(s)`,T>0?"success":"error")}catch(m){const p=m instanceof Error?m.message:"Unknown error";s&&(s.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: rgba(239,68,68,0.1); color: var(--danger-color);">
            <strong>❌ Failed:</strong> ${p}
          </div>
        `),x("Failed to trigger all push-to-starts","error")}finally{e.disabled=!1,e.textContent=t}}async triggerPushToStart(e){var o,l,c,d,h,u,f,m,p,T,P,M;const t=(c=(l=(o=this.container)==null?void 0:o.querySelector("#debug-event-id"))==null?void 0:l.value)==null?void 0:c.trim(),s=(u=(h=(d=this.container)==null?void 0:d.querySelector("#debug-home-team"))==null?void 0:h.value)==null?void 0:u.trim(),n=(p=(m=(f=this.container)==null?void 0:f.querySelector("#debug-away-team"))==null?void 0:m.value)==null?void 0:p.trim();if(!t){x("Event ID is required — select one from the registrations above","error");return}const a=e.textContent;e.disabled=!0,e.textContent="Sending...";const i=(T=this.container)==null?void 0:T.querySelector("#debug-result");try{const S=await C.triggerDebugPushToStart(t,s||"Debug Lions",n||"Debug Tigers");if(i){const k={no_registrations:"No push-to-start tokens found in Redis",apns_not_configured:"APNS not configured (missing APNSkeyID/TeamID env vars)",no_match:"Registrations exist but no favorites or event IDs matched"},L=S.reason?k[S.reason]||S.reason:"";i.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: ${S.notified>0?"rgba(34,197,94,0.1)":"rgba(234,179,8,0.1)"};">
            <strong>${S.notified>0?"✅":"⚠️"} Notified ${S.notified} device(s)</strong>
            ${(P=S.tokens)!=null&&P.length?`<div style="margin-top: 0.5rem; font-family: monospace; font-size: 0.8rem; color: var(--text-secondary);">Tokens: ${S.tokens.join(", ")}</div>`:""}
            ${L?`<div style="margin-top: 0.5rem; color: var(--warning-color, #eab308); font-weight: 600;">${L}</div>`:""}
            ${(M=S.errors)!=null&&M.length?`<div style="margin-top: 0.5rem; color: var(--danger-color);"><strong>APNS Errors:</strong><pre style="margin: 0.25rem 0; font-size: 0.75rem; white-space: pre-wrap;">${S.errors.join(`
`)}</pre></div>`:""}
            ${S.trace?`<details style="margin-top: 0.75rem;"><summary style="cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);">Server Trace</summary><pre style="margin-top: 0.5rem; padding: 0.75rem; background: var(--bg-color); border: 1px solid var(--border-color); border-radius: 0.25rem; font-size: 0.7rem; white-space: pre-wrap; overflow-x: auto; color: var(--text-secondary);">${S.trace}</pre></details>`:""}
          </div>
        `}x(`Push-to-start sent to ${S.notified} device(s)`,S.notified>0?"success":"error")}catch(S){const k=S instanceof Error?S.message:"Unknown error";i&&(i.innerHTML=`
          <div style="padding: 1rem; border-radius: 0.375rem; background: rgba(239,68,68,0.1); color: var(--danger-color);">
            <strong>❌ Request Failed:</strong> ${k}
            <div style="margin-top: 0.5rem; font-size: 0.875rem; color: var(--text-secondary);">Make sure the Vapor server is running.</div>
          </div>
        `),x("Failed to trigger push-to-start","error")}finally{e.disabled=!1,e.textContent=a}}}class jt{constructor(){g(this,"container",null);g(this,"eventSource",null);g(this,"consoleEl",null);g(this,"autoScroll",!0)}render(e){this.container=e,this.container.innerHTML=`
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
`,t==="stderr"&&(s.style.color="#f85149"),this.consoleEl.appendChild(s);this.consoleEl.childNodes.length>5e3;)this.consoleEl.removeChild(this.consoleEl.firstChild);this.autoScroll&&(this.consoleEl.scrollTop=this.consoleEl.scrollHeight)}updateState(e,t,s){const n=document.getElementById("server-badge"),a=document.getElementById("server-pid"),i=document.getElementById("srv-start"),o=document.getElementById("srv-stop"),l=document.getElementById("srv-restart");if(!n)return;const c={stopped:"#6b7280",building:"#f59e0b",running:"#22c55e",error:"#ef4444"};n.textContent=e.toUpperCase(),n.style.background=c[e]??"#6b7280",n.style.color="#fff",a&&(a.textContent=t?`PID ${t}`:""),i&&(i.disabled=e==="running"||e==="building"),o&&(o.disabled=e==="stopped"),l&&(l.disabled=e==="stopped"),s&&this.appendLine(`ERROR: ${s}`,"stderr")}async checkExternalProcess(){try{const t=await(await fetch("/__server/status")).json(),s=document.getElementById("srv-force-kill");if(!s)return;t.state==="stopped"?s.style.display="inline-block":s.style.display="none"}catch{}}}class Bt{constructor(){g(this,"container",null);g(this,"ws",null);g(this,"entries",[]);g(this,"maxEntries",2e3);g(this,"paused",!1);g(this,"autoScroll",!0);g(this,"seenLabels",new Set);g(this,"filter",{level:"debug",labels:[],search:""});g(this,"searchDebounce",null)}render(e){this.container=e,this.entries=[],this.seenLabels=new Set,e.innerHTML=`
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
    `,this.setupEventListeners(),this.connect()}stop(){this.disconnect()}setupEventListeners(){if(!this.container)return;this.container.querySelectorAll(".log-level-btn").forEach(i=>{i.addEventListener("click",()=>{i.classList.toggle("active"),this.updateMinLevel(),this.renderEntries()})});const e=this.container.querySelector("#logs-search");e==null||e.addEventListener("input",()=>{this.searchDebounce&&clearTimeout(this.searchDebounce),this.searchDebounce=setTimeout(()=>{this.filter.search=e.value,this.sendFilter(),this.renderEntries()},300)});const t=this.container.querySelector("#logs-label-select");t==null||t.addEventListener("change",()=>{this.filter.labels=t.value?[t.value]:[],this.sendFilter(),this.renderEntries()});const s=this.container.querySelector("#logs-pause");s==null||s.addEventListener("click",()=>{this.paused=!this.paused,s.textContent=this.paused?"Resume":"Pause"});const n=this.container.querySelector("#logs-clear");n==null||n.addEventListener("click",()=>{this.entries=[],this.renderEntries()});const a=this.container.querySelector("#logs-list");a==null||a.addEventListener("scroll",()=>{if(!a)return;const i=a;this.autoScroll=i.scrollHeight-i.scrollTop-i.clientHeight<50})}updateMinLevel(){var n;const e=["debug","info","warning","error"],t=(n=this.container)==null?void 0:n.querySelectorAll(".log-level-btn.active"),s=new Set;t==null||t.forEach(a=>{const i=a.dataset.level;i&&s.add(i)});for(const a of e)if(s.has(a)){this.filter.level=a,this.sendFilter();return}this.filter.level="error",this.sendFilter()}connect(){const t=`${window.location.protocol==="https:"?"wss:":"ws:"}//${window.location.host}/ws/logs`;try{this.ws=new WebSocket(t),this.ws.onmessage=s=>{if(!this.paused)try{const n=JSON.parse(s.data);n.type==="initial"&&Array.isArray(n.entries)?(this.entries=n.entries,n.entries.forEach(a=>this.seenLabels.add(a.label)),this.updateLabelSelect(),this.renderEntries()):n.type==="entry"&&n.entry&&this.addEntry(n.entry)}catch{}},this.ws.onclose=()=>{setTimeout(()=>{this.container&&this.connect()},3e3)}}catch{}}disconnect(){this.ws&&(this.ws.onclose=null,this.ws.close(),this.ws=null)}addEntry(e){var s;this.entries.push(e),this.entries.length>this.maxEntries&&(this.entries=this.entries.slice(-this.maxEntries));const t=!this.seenLabels.has(e.label);if(this.seenLabels.add(e.label),t&&this.updateLabelSelect(),this.matchesClientFilter(e)){const n=(s=this.container)==null?void 0:s.querySelector("#logs-list");n&&(n.appendChild(this.createEntryElement(e)),this.autoScroll&&(n.scrollTop=n.scrollHeight))}this.updateCount()}matchesClientFilter(e){var l;const t=["trace","debug","info","notice","warning","error","critical"],s=t.indexOf(e.level),n=t.indexOf(this.filter.level);if(s<n)return!1;const a=(l=this.container)==null?void 0:l.querySelectorAll(".log-level-btn.active"),i=new Set;a==null||a.forEach(c=>{const d=c.dataset.level;d&&i.add(d)});const o=e.level==="notice"?"info":e.level;return!(!i.has(o)||this.filter.labels.length>0&&!this.filter.labels.includes(e.label)||this.filter.search&&!e.message.toLowerCase().includes(this.filter.search.toLowerCase())&&!e.label.toLowerCase().includes(this.filter.search.toLowerCase()))}renderEntries(){var n;const e=(n=this.container)==null?void 0:n.querySelector("#logs-list");if(!e)return;const t=this.entries.filter(a=>this.matchesClientFilter(a)),s=document.createDocumentFragment();for(const a of t)s.appendChild(this.createEntryElement(a));e.innerHTML="",e.appendChild(s),this.autoScroll&&(e.scrollTop=e.scrollHeight),this.updateCount()}createEntryElement(e){const t=document.createElement("div");t.className=`log-entry log-level-${e.level}`;const s=new Date(e.timestamp).toLocaleTimeString("en-US",{hour12:!1,hour:"2-digit",minute:"2-digit",second:"2-digit",fractionalSecondDigits:3}),n=e.level.toUpperCase().padEnd(5),a=Object.keys(e.metadata).length>0?`<span class="log-metadata">${Object.entries(e.metadata).map(([i,o])=>`${i}=${o}`).join(" ")}</span>`:"";return t.innerHTML=`<span class="log-time">${s}</span><span class="log-level-badge log-badge-${e.level}">${n}</span><span class="log-label">${e.label}</span><span class="log-separator">│</span><span class="log-message">${this.escapeHtml(e.message)}</span>${a}`,Object.keys(e.metadata).length>0&&(t.style.cursor="pointer",t.addEventListener("click",()=>{const i=t.querySelector(".log-metadata-expanded");if(i)i.remove();else{const o=document.createElement("div");o.className="log-metadata-expanded",o.textContent=JSON.stringify(e.metadata,null,2),t.appendChild(o)}})),t}escapeHtml(e){const t=document.createElement("div");return t.textContent=e,t.innerHTML}updateLabelSelect(){var n;const e=(n=this.container)==null?void 0:n.querySelector("#logs-label-select");if(!e)return;const t=e.value,s=Array.from(this.seenLabels).sort();e.innerHTML='<option value="">All subsystems</option>'+s.map(a=>`<option value="${a}"${a===t?" selected":""}>${a}</option>`).join("")}updateCount(){var s,n,a;const e=(s=this.container)==null?void 0:s.querySelector("#logs-count");if(!e)return;const t=((a=(n=this.container)==null?void 0:n.querySelector("#logs-list"))==null?void 0:a.children.length)??0;e.textContent=`${t} / ${this.entries.length} entries`}sendFilter(){var e;((e=this.ws)==null?void 0:e.readyState)===WebSocket.OPEN&&this.ws.send(JSON.stringify({type:"filter",level:this.filter.level,labels:this.filter.labels.length>0?this.filter.labels:void 0,search:this.filter.search||void 0}))}}class _t{constructor(){g(this,"currentView","");g(this,"components",new Map);g(this,"mainContent");this.mainContent=document.getElementById("main-content"),this.components.set("health",new zt),this.components.set("live",new Ot),this.components.set("leagues",new Wt),this.components.set("gaps",new Gt),this.components.set("redis",new Nt),this.components.set("teams",new It),this.components.set("debug",new qt),this.components.set("server",new jt),this.components.set("logs",new Bt),this.setupNavigation(),this.showView("health")}setupNavigation(){document.querySelectorAll(".nav-btn").forEach(t=>{t.addEventListener("click",s=>{const n=s.target.dataset.view;n&&this.showView(n)})})}showView(e){if(this.currentView===e)return;document.querySelectorAll(".nav-btn").forEach(n=>{n instanceof HTMLElement&&n.classList.toggle("active",n.dataset.view===e)});const t=this.components.get(this.currentView);t!=null&&t.stop&&t.stop(),this.currentView=e;const s=this.components.get(e);s&&(this.mainContent.innerHTML="",s.render(this.mainContent))}}document.addEventListener("DOMContentLoaded",()=>{new _t});

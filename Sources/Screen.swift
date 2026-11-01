import Foundation

/// הדף עצמו. נטען פעם אחת, ואחר כך רק מקבל נתונים דרך paint().
///
/// למה דפדפן ולא ציור מקומי: המסוף של אפל מיישם שגוי את אלגוריתם הדו־כיווניות,
/// ומנוע־הדפדפן מיישם אותו נכון. זו כל הסיבה שהמסך הזה קיים.
enum Screen {

    static let html = """
<!doctype html>
<html dir="\(Lang.dir)" lang="\(Lang.code)">
<head>
<meta charset="utf-8">
<style>
/* ---------- קסקדיה מונו על הכל ---------- */
/* קסקדיה נושאת את כל 27 האותיות העבריות (נמדד). פונט עברי מאחוריה לא ירונדר
   לעולם, ולכן אין כאן שכבת־גיבוי עברית — רק רצפה גנרית אם הפונט חסר. */
* { font-family: 'Cascadia Mono', monospace; box-sizing: border-box; }

:root {
  --ground: #0a0b0c;
  --rack:   #101315;
  --line:   #1b1f22;
  --edge:   #2a3034;
  --text:   #d7dad5;
  --dim:    #757b74;
  --faint:  #454b48;
  --run:    #63d18c;
  --wait:   #f0a63c;
  --idle:   #4c534f;
  --peach:  #f2a365;
}

html, body {
  margin: 0; height: 100%;
  background: var(--ground);
  color: var(--text);
  font-size: 13px;
  line-height: 1.55;
  -webkit-font-smoothing: antialiased;
  font-variant-numeric: tabular-nums;
  overflow: hidden;
}

#grain {
  position: fixed; inset: 0; z-index: 9; pointer-events: none;
  background: repeating-linear-gradient(
      to bottom, rgba(255,255,255,0.022) 0 1px, transparent 1px 3px);
}

/* ---------- כותרות ---------- */
/* ⛔ **שאלה במסוף אחר, בזמן שאתה קורא שיחה.** נמדד 30.8: שאלה הייתה
   פתוחה 4:29 בלי שאיש ידע, כי מי שיושב בתוך שיחה היה עיוור לכל השאר.
   ⇒ הרצועה יושבת בין הכותרת לגוף — במסלול העין, ולא בפינה. */
#alerts {
  flex: none; display: none; flex-wrap: wrap; gap: 8px 14px;
  padding: 7px 20px; background: var(--rack);
  border-bottom: 1px solid var(--wait); font-size: 11.5px;
}
#alerts.on { display: flex; }
#alerts .lead { color: var(--wait); }
#alerts .who {
  cursor: pointer; color: var(--dim);
  border: 1px solid var(--line); padding: 2px 9px;
  display: inline-flex; gap: 8px; align-items: baseline;
}
#alerts .who:hover { color: var(--text); border-color: var(--wait); }
#alerts .who b { color: var(--wait); font-weight: 400; }
/* ⇒ הטקסט של השאלה נחתך, אבל **הוא שם**: "ממתין לך" אינו אומר על מה. */
#alerts .what {
  color: var(--faint); max-width: 46ch;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}

header, #chatbar, #findbar {
  flex: none; background: var(--ground);
  border-bottom: 1px solid var(--edge);
  padding: 40px 20px 10px 20px;
  display: flex; align-items: baseline; gap: 16px;
}
#name { font-size: 17px; font-weight: 700; letter-spacing: 0.02em; }
/* ---------- הסמליל: אפרסק בתוך מקלט ---------- */
/* מקלט־טלוויזיה ישן בקו אחד, ובתוכו אפרסק שמסתובב לפי מה שקורה במסופים.
   בלי זוהר ובלי צל — האפקט היחיד הוא סריקה שעוברת על המסך, כמו שהיה. */
.mark { display: inline-block; vertical-align: -0.22em; }
/* הסמליל הוא כפתור: לחיצה מסדרת את המדף מחדש */
#logo { cursor: pointer; display: inline-block; }
#logo:hover .mark .set { stroke: var(--peach); }
#logo.thump { animation: thump 420ms ease-out; }
@keyframes thump {
  0% { transform: scale(1); } 32% { transform: scale(0.86); } 100% { transform: scale(1); }
}
.mark .set { fill: none; stroke: var(--edge); stroke-width: 3; }
.mark .glass { fill: #07080a; }
.mark .knob { fill: var(--edge); }
.mark .scan {
  stroke: var(--peach); stroke-width: 2; opacity: 0.30;
  animation: sweep 3.2s linear infinite;
}
@keyframes sweep { from { transform: translateY(0); } to { transform: translateY(52px); } }

/* התפוז עצמו יושב בעולם תלת־ממדי קטן, ולכן הסיבוב נראה כסיבוב ולא כהיפוך */
.spin { perspective: 220px; display: inline-block; }
.fruit {
  transform-style: preserve-3d;
  animation: turn var(--spin, 9s) linear infinite;
}
.fruit.still { animation-play-state: paused; }
@keyframes turn { from { transform: rotateY(0deg); } to { transform: rotateY(360deg); } }
.fruit .skin { fill: var(--peach); }
.fruit .cleft { fill: none; stroke: #b8703a; stroke-width: 2.4; opacity: 0.85; }
.fruit .leaf { fill: var(--run); }

#caret {
  display: inline-block; width: 0.55em; height: 1em; margin-right: 3px;
  background: var(--run); vertical-align: -0.13em;
  animation: blink 1.1s steps(2, jump-none) infinite;
}
@keyframes blink { 50% { opacity: 0.15; } }

.btn {
  cursor: pointer; color: var(--dim); font-size: 12px;
  border: 1px solid var(--edge); padding: 3px 10px; white-space: nowrap;
  transition: color 90ms linear, border-color 90ms linear;
}
.btn:hover { color: var(--text); border-color: var(--dim); }

#readout { margin-inline-start: auto; display: flex; gap: 18px; align-items: baseline; }
.stat { display: flex; gap: 6px; align-items: baseline; }
.stat .n { font-size: 15px; font-weight: 700; }
.stat .l { font-size: 11px; color: var(--dim); letter-spacing: 0.06em; }
.stat.run  .n { color: var(--run); }
.stat.wait .n { color: var(--wait); }
#clock { font-size: 12px; color: var(--faint); }

/* ---------- מסכים ---------- */
.view { display: none; height: 100%; flex-direction: column; }
.view.on { display: flex; }
body > .view { height: 100vh; }

.scroll { flex: 1; overflow-y: auto; }
.scroll::-webkit-scrollbar { width: 9px; }
.scroll::-webkit-scrollbar-thumb { background: var(--edge); }
.scroll::-webkit-scrollbar-track { background: transparent; }

/* ---------- מדף המסופים ---------- */
.unit {
  display: grid;
  grid-template-columns: 5.5ch \(Lang.t("12ch", "18ch")) 1fr auto;
  /* ⛔ **עמודת־הנורית ברוחב קבוע, וזה מכוון** — כותרת שמתחילה
     במקום אחר בכל שורה הורסת את זיכרון־השריר של המדף.
     ⚠ אבל הרוחב תלוי־שפה: ״ממתין לך״ הוא שמונה תווים ו-
     "waiting for you" הוא חמישה־עשר, ובאנגלית הוא גלש
     ודרס את הכותרת. נמדד על רינדור, לא שוער. */
  grid-template-areas: "slot lamp head meta" "slot lamp sub sub";
  column-gap: 14px;
  padding: 11px 20px;
  border-bottom: 1px solid var(--line);
  cursor: pointer;
  transition: background-color 90ms linear;
}
.unit:hover { background: var(--rack); }
.unit:hover .hint { opacity: 1; }
.slot {
  grid-area: slot; align-self: start;
  direction: ltr; unicode-bidi: isolate; text-align: left;
  font-size: 19px; font-weight: 700; color: var(--faint);
  letter-spacing: -0.02em;
}
.unit.run  .slot { color: var(--text); }
.unit.wait .slot { color: var(--wait); }
.lamp { grid-area: lamp; align-self: start; display: flex; gap: 8px; align-items: baseline; }
.bulb { width: 8px; height: 8px; flex: none; align-self: center; }
.unit.run  .bulb { background: var(--run); }
.unit.wait .bulb { background: var(--wait); }
.unit.quiet .bulb, .unit.closed .bulb {
  background: transparent; box-shadow: inset 0 0 0 1px var(--idle);
}
.state { font-size: 12px; letter-spacing: 0.04em; white-space: nowrap; }
.unit.run  .state { color: var(--run); }
.unit.wait .state { color: var(--wait); }
.unit.quiet .state { color: var(--idle); }
.head {
  grid-area: head; align-self: start;
  font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.unit.quiet .head { color: var(--dim); }
.meta {
  grid-area: meta; align-self: start;
  display: flex; gap: 14px; align-items: baseline;
  font-size: 12px; color: var(--dim); white-space: nowrap;
}
.age { color: var(--dim); }
.unit.run .age, .unit.wait .age { color: var(--text); }
.pair { display: flex; gap: 5px; align-items: baseline; }
.pair .num { color: var(--text); }
.pair .l { color: var(--dim); font-size: 11px; letter-spacing: 0.04em; }
.pair .money { color: var(--peach); direction: ltr; unicode-bidi: isolate; }
/* שיחה שמתמלאת — לפני שהיא מאבדת את עצמה */
.pair.heavy .num { color: var(--wait); font-weight: 700; }
.pair.heavy .l { color: var(--wait); }
.pair.warm .num, .pair.warm .l { color: var(--peach); }
/* The relay's one click — always visible, not only on hover. */
.quick.relay { opacity: 1; }
.quick span.relaygo { color: var(--peach); border-color: var(--peach); }
.quick span.relaygo:hover { color: var(--ground); background: var(--peach); }
.quick span.relaywait { cursor: default; }
.unit.quiet .pair .money { color: #a4703f; }
.unit.quiet .pair .num { color: var(--dim); }
.sep { color: var(--faint); }
.sub {
  grid-area: sub; margin-top: 3px;
  display: flex; gap: 12px; align-items: baseline;
  font-size: 12px; color: var(--dim); overflow: hidden;
}
.say { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.unit.run .say { color: var(--text); }
.path {
  margin-inline-start: auto; flex: none;
  direction: ltr; unicode-bidi: isolate; text-align: left;
  color: var(--faint); font-size: 11px; cursor: pointer;
}
.path:hover { color: var(--peach); }
.path.on { color: var(--peach); }

/* ⇒ שאלה שנראית על המסך ואין לה עדיין שורה ביומן: אפשר לקפוץ, לא לענות. */
.raw {
  cursor: pointer; color: var(--wait); border: 1px solid var(--wait);
  padding: 1px 8px; font-size: 10.5px; margin-inline-start: 10px;
}
.raw:hover { background: var(--wait); color: var(--ground); }
/* ⇒ שורה ששואלת אותך ונשאבה פנימה למרות הסינון — מסומנת, אחרת היא
   נראית כמו הפרה שרירותית של הסינון שהמשתמש עצמו הפעיל. */
.path.outside { color: var(--wait); border-bottom: 1px dotted var(--wait); }
#sift {
  flex: none; display: none; align-items: baseline; gap: 10px;
  padding: 7px 20px; background: var(--rack); border-bottom: 1px solid var(--line);
  font-size: 11.5px; color: var(--dim);
}
#sift.on { display: flex; }
#sift b { color: var(--peach); font-weight: 400; direction: ltr; unicode-bidi: isolate; }
#sift b.pulled { color: var(--wait); direction: rtl; }
#sift span { cursor: pointer; color: var(--faint); margin-inline-start: auto; }
#sift span:hover { color: var(--text); }
.hint { flex: none; color: var(--faint); font-size: 11px;
        opacity: 0; transition: opacity 90ms linear; }

/* תשובה קצרה ישר מהשורה. תמיד גלויה כשהמסוף ממתין לך, ובריחוף בשאר. */
.quick { flex: none; display: flex; gap: 6px; opacity: 0;
         transition: opacity 90ms linear; }
.unit:hover .quick, .unit.wait .quick { opacity: 1; }
.quick span {
  cursor: pointer; font-size: 11px; color: var(--dim);
  border: 1px solid var(--edge); padding: 1px 8px; white-space: nowrap;
  transition: color 90ms linear, border-color 90ms linear;
}
.unit.muted { opacity: .55; }
.unit.muted .quick { opacity: 1; }
.unit .head .pen { margin-inline-start: 8px; font-size: 12px; color: var(--faint); cursor: pointer; opacity: 0; }
.unit:hover .head .pen { opacity: 1; }
.unit .head .pen:hover { color: var(--peach); }
.unit .head .nm.editing { outline: 1px solid var(--peach); padding: 0 4px; cursor: text; }
.quick span:hover { color: var(--peach); border-color: var(--peach); }
.quick span.sent { color: var(--run); border-color: #245c3d; }
#wakeall { color: var(--wait); border-color: #6b4a1c; }
#wakeall:hover { color: var(--ground); background: var(--wait); border-color: var(--wait); }
#wakeall.off { display: none; }
.agents { flex: none; color: var(--wait); }
#empty { padding: 60px 20px; color: var(--dim); text-align: center; }
.unit.pick { background: var(--rack); box-shadow: inset 2px 0 0 var(--peach); }

/* ---------- רצועת־הסוכנים בתוך השיחה ---------- */
/* ⛔ סוכן שרץ בשיחה שקטה הוא הסיבה שחיווי "דומם" לבדו משקר. הרצועה יושבת
   מעל שורת־ההקלדה ולא בתוך היומן: היא **מצב עכשיו**, לא דבר שנאמר. */
#crewstrip {
  flex: none; display: none; flex-direction: column;
  background: var(--rack); border-top: 1px solid var(--edge);
}
#crewstrip.on { display: flex; }
.crewline {
  display: grid; grid-template-columns: 1.6ch 12ch 1fr 11ch 7ch 6ch; gap: 11px;
  align-items: baseline; padding: 6px 20px; font-size: 12px;
  border-bottom: 1px solid var(--line); cursor: pointer;
}
.crewline:last-child { border-bottom: 0; }
.crewline:hover { background: #141719; }
.crewline .beat { color: var(--run); font-size: 11px; }
.crewline .kind {
  color: var(--peach); font-size: 11px; unicode-bidi: plaintext; text-align: right;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.crewline .what {
  color: var(--text); unicode-bidi: plaintext; text-align: right;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.crewline .now { color: var(--run); font-size: 11px; white-space: nowrap; }
.crewline .lap, .crewline .ctx {
  color: var(--dim); font-size: 11px; white-space: nowrap;
  direction: ltr; unicode-bidi: isolate; text-align: start;
}
#crewmore { padding: 5px 20px 7px 20px; font-size: 11px; color: var(--faint); cursor: pointer; }
#crewmore:hover { color: var(--dim); }

/* ---------- ראש היומן: עוד מההתחלה ---------- */
#earlier {
  display: flex; align-items: center; gap: 12px;
  padding: 10px 20px; border-bottom: 1px solid var(--line);
  font-size: 12px; color: var(--dim); cursor: pointer;
  transition: color 90ms linear;
}
#earlier:hover { color: var(--text); }
#earlier.done { cursor: default; color: var(--faint); }
#earlier.done:hover { color: var(--faint); }
#earlier hr { flex: 1; border: 0; border-top: 1px solid var(--line); margin: 0; }
#earlier b { font-weight: 700; }

/* ---------- חוגת־המספרים: ספרה במקלדת פותחת מסוף ---------- */
/* מספר־העמדה הוא הדבר הראשון שהעין תופסת בשורה, ולכן הוא גם הדרך המהירה
   ביותר להגיע אליה. ההקלדה נאספת לחלון קצר, כדי ש-"20" לא ייקרא כ-"2". */
#dial {
  position: fixed; z-index: 12; inset-inline-start: 20px; bottom: 20px;
  display: none; align-items: baseline; gap: 12px;
  background: var(--rack); border: 1px solid var(--peach);
  padding: 8px 14px 9px 14px;
}
#dial.on { display: flex; }
#dial.miss { border-color: #7a4038; }
#dial .digits {
  direction: ltr; unicode-bidi: isolate;
  font-size: 22px; font-weight: 700; color: var(--peach); letter-spacing: 0.06em;
}
#dial.miss .digits { color: #b8635a; }
#dial .what {
  font-size: 12px; color: var(--dim); max-width: 46ch;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.unit.aim { background: var(--rack); }
.unit.aim .slot { color: var(--peach); }

/* ---------- מכסת־המנוי ---------- */
#quota { padding: 16px 20px 4px 20px; border-bottom: 1px solid var(--line); }
.qrow {
  display: grid; grid-template-columns: 15ch 1fr 5ch 7ch 24ch; gap: 12px;
  align-items: center; padding: 5px 0;
}
.qrow .ql { font-size: 12.5px; color: var(--dim); }
.qrow.live .ql { color: var(--text); }
.qtrack { height: 9px; background: #171b1d; box-shadow: inset 0 0 0 1px var(--line); }
.qfill { height: 100%; background: var(--peach); min-width: 2px; }
.qrow.warn .qfill { background: var(--wait); }
.qrow.critical .qfill { background: #d9614f; }
.qrow .qp {
  direction: ltr; unicode-bidi: isolate; text-align: start;
  font-size: 14px; font-weight: 700; color: var(--text);
}
.qrow .qw { font-size: 11px; color: var(--faint); white-space: nowrap;
            overflow: hidden; text-overflow: ellipsis; }
.qrow .qb {
  direction: ltr; unicode-bidi: isolate; text-align: start;
  font-size: 11px; color: var(--peach);
}
#quotanote { padding: 6px 0 2px 0; font-size: 11px; color: var(--faint); }
#quotanote.warn { color: var(--wait); }

/* ---------- מסך־הצריכה ---------- */
#spendview .scroll { padding-bottom: 40px; }
#spendhead {
  display: flex; gap: 26px; align-items: flex-end;
  padding: 16px 20px 14px 20px; border-bottom: 1px solid var(--line);
}
.big { display: flex; flex-direction: column; gap: 2px; }
.big .v {
  direction: ltr; unicode-bidi: isolate; text-align: start;
  font-size: 27px; font-weight: 700; color: var(--peach); line-height: 1.1;
}
.big.side .v { font-size: 17px; color: var(--text); }
.big .l { font-size: 11px; color: var(--dim); letter-spacing: 0.06em; }
#spendhead .spacer { flex: 1; }

/* עמודה ליום. הגובה הוא היחס לגבוה ביותר — סרגל מוחלט לא היה אומר דבר. */
#bars { display: flex; gap: 4px; align-items: flex-end; height: 56px; direction: ltr; }
.bar { width: 25px; display: flex; flex-direction: column; justify-content: flex-end;
       height: 100%; gap: 3px; }
.bar i { display: block; background: #6b4527; min-height: 2px; }
.bar.now i { background: var(--peach); }
.bar b { font-size: 9px; color: var(--faint); font-weight: 400; text-align: center;
         direction: ltr; unicode-bidi: isolate; }
.bar.now b { color: var(--dim); }

.spendrow {
  display: grid; grid-template-columns: 9ch 1fr 8ch 11ch 11ch; gap: 14px;
  align-items: baseline; padding: 8px 20px; border-bottom: 1px solid var(--line);
  font-size: 12.5px; cursor: default; white-space: nowrap;
}
.spendrow.live { cursor: pointer; }
.spendrow.live:hover { background: var(--rack); }
.spendrow .money {
  direction: ltr; unicode-bidi: isolate; text-align: start;
  color: var(--peach); font-weight: 700;
}
.spendrow .nm { unicode-bidi: plaintext; text-align: right; overflow: hidden;
                text-overflow: ellipsis; white-space: nowrap; }
.spendrow .nm { color: var(--dim); }
.spendrow.live .nm { color: var(--text); }
.spendrow .md { color: var(--faint); font-size: 11px; }
.spendrow .tok, .spendrow .cl {
  direction: ltr; unicode-bidi: isolate; text-align: start;
  color: var(--faint); font-size: 11px;
}
.spendbar { display: flex; height: 6px; margin: 0 20px 14px 20px; gap: 2px; }
.spendbar span { display: block; }
.spendhr {
  display: flex; gap: 10px; align-items: baseline;
  padding: 13px 20px 7px 20px; font-size: 11px; color: var(--dim);
  letter-spacing: 0.06em;
}
.spendhr hr { flex: 1; border: 0; border-top: 1px solid var(--line); margin: 0; }
#spendnote { padding: 40px 20px; color: var(--dim); text-align: center; }
.mono { direction: ltr; unicode-bidi: isolate; }

/* ---------- שאלות שממתינות לך ---------- */
#askslist { padding-bottom: 40px; }
.ask { border-bottom: 1px solid var(--line); padding: 14px 20px; }
.askhead { display: flex; gap: 11px; align-items: baseline; cursor: pointer; }
.askdot { flex: none; font-size: 12px; }
.askid {
  flex: none; direction: ltr; unicode-bidi: isolate;
  font-size: 11px; color: var(--faint); letter-spacing: .05em;
}
.asktitle { flex: 1; min-width: 0; font-size: 14px; font-weight: 700; }
.ask.done .asktitle { color: var(--dim); font-weight: 400; }
.askcost {
  flex: none; font-size: 11px; color: var(--peach);
  border: 1px solid var(--pit); padding: 1px 8px; white-space: nowrap;
}
.ask.done .askcost { color: var(--run); border-color: #245c3d; }
.askfrom { flex: none; font-size: 11px; color: var(--faint); white-space: nowrap; }
.askbody { display: none; margin-top: 11px; }
.ask.open .askbody { display: block; }
.askbody .md { font-size: 12.5px; color: var(--dim); }
.askreply { display: flex; gap: 9px; margin-top: 12px; align-items: flex-start; }
.askreply textarea {
  flex: 1; min-height: 3.2em; resize: vertical;
  background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); outline: none; padding: 8px 10px;
  font-size: 13px; line-height: 1.5;
}
.askreply textarea:focus { border-color: var(--dim); }
.asksaid {
  margin-top: 10px; padding: 8px 11px; border-inline-start: 2px solid var(--run);
  background: var(--rack); font-size: 12.5px; color: var(--text);
}

/* ---------- תוצרים ---------- */
.workday {
  font-size: 11px; color: var(--peach); letter-spacing: .12em;
  padding: 16px 20px 6px 20px; border-bottom: 1px solid var(--line);
}
.workday.gone { display: none; }
.workcard .workfolder { unicode-bidi: plaintext; color: var(--faint); max-width: 34ch;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.findsec { font-size: 11px; color: var(--peach); letter-spacing: .12em; padding: 14px 20px 6px 20px; }
.filehit {
  display: grid; grid-template-columns: 1fr auto auto auto auto; gap: 14px; align-items: baseline;
  padding: 8px 20px; border-bottom: 1px solid var(--line); cursor: pointer; font-size: 13px;
  transition: background-color 90ms linear;
}
.filehit:hover, .filehit.pick { background: var(--rack); }
.filehit .fn { unicode-bidi: plaintext; text-align: start; color: var(--text); overflow-wrap: anywhere; }
.filehit:hover .fn { color: var(--peach); }
.filehit .fd { unicode-bidi: plaintext; color: var(--faint); font-size: 11px; max-width: 40ch;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.filehit .fk { color: var(--peach); font-size: 11px; }
.filehit .fa { color: var(--faint); font-size: 11px; white-space: nowrap; }
.filehit .fw { grid-column: 1 / -1; font-size: 12px; color: var(--dim); unicode-bidi: plaintext; }
.filehit .fo { color: var(--faint); font-size: 11px; cursor: pointer; }
.filehit .fo:hover { color: var(--flesh); }
#worksbar {
  flex: none; display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
  padding: 40px 20px 10px 20px;
  background: var(--ground); border-bottom: 1px solid var(--line);
}
#worksfind {
  flex: 1; min-width: 140px; background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); outline: none; padding: 7px 10px; font-size: 13px;
}
#worksfind:focus { border-color: var(--dim); }
#worksfind::placeholder { color: var(--faint); }
#workscount { flex: none; font-size: 12px; color: var(--dim); white-space: nowrap; }

/* מסננים כשורת־צ׳יפים: לחיצה אחת, בלי תפריט שנפתח ובלי אישור */
.sift {
  flex: none; display: flex; gap: 6px; align-items: center; flex-wrap: wrap;
  padding: 8px 20px; border-bottom: 1px solid var(--line); background: var(--ground);
}
.sift .lbl { font-size: 10px; color: var(--faint); letter-spacing: .12em; margin-inline-end: 4px; }
.pill {
  cursor: pointer; font-size: 11px; color: var(--dim);
  border: 1px solid var(--rule); padding: 2px 9px; white-space: nowrap;
  transition: color 90ms linear, border-color 90ms linear;
}
.pill:hover { color: var(--text); }
.pill.on { color: var(--peach); border-color: var(--pit); }

.workcard { margin: 0 14px; }
/* A closed file is a plain line, not a box — boxes stacked 500 deep read as
   a wall (reported 7.10). It becomes a card again only when opened. */
.workcard.shut { border: 0; border-bottom: 1px solid var(--line); background: transparent; }
.workcard.shut:hover { background: var(--rack); }
.workcard .cardname { unicode-bidi: plaintext; direction: auto; text-align: start; font-size: 12.5px; }
.workcard .cardbar { cursor: pointer; }
.workcard .workkind { color: var(--peach); }
.workcard .workproj { unicode-bidi: plaintext; max-width: 22ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.work {
  display: grid; grid-template-columns: 1fr 9ch 14ch 7ch 6ch; gap: 12px;
  align-items: baseline; padding: 8px 20px; border-bottom: 1px solid var(--line);
  cursor: pointer; transition: background-color 90ms linear; font-size: 12.5px;
}
.work:hover { background: var(--rack); }
.work.gone { display: none; }
.work .nm { unicode-bidi: plaintext; text-align: start; overflow-wrap: anywhere; color: var(--text); }
.work:hover .nm { color: var(--flesh); }
.work .kd { color: var(--peach); font-size: 11px; }
.work .pj { color: var(--dim); font-size: 11px; unicode-bidi: plaintext; overflow: hidden;
            text-overflow: ellipsis; white-space: nowrap; }
.work .ag, .work .sz { color: var(--faint); font-size: 11px; white-space: nowrap; }

/* ---------- ספר־היכולות ---------- */
#bookbar {
  flex: none; display: flex; align-items: center; gap: 14px;
  padding: 40px 20px 12px 20px;
  background: var(--ground); border-bottom: 1px solid var(--edge);
}
#booksift {
  flex: 1; min-width: 0; background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); outline: none; padding: 7px 10px; font-size: 13px;
}
#booksift:focus { border-color: var(--dim); }
#booksift::placeholder { color: var(--faint); }
#bookcount { flex: none; font-size: 12px; color: var(--dim); white-space: nowrap; }

.fam { margin: 22px 0 0; }
.fam.gone { display: none; }
.famhead {
  display: flex; align-items: baseline; gap: 11px;
  padding: 0 20px 7px; }
.famhead h4 { margin: 0; font-size: 13px; font-weight: 700; }
.famhead em { font-style: normal; color: var(--peach); font-size: 11px; }
.famhead hr { flex: 1; border: 0; border-top: 1px solid var(--line); margin: 0; }

.skill {
  display: grid; grid-template-columns: 24ch 7ch 1fr; gap: 14px; align-items: baseline;
  padding: 7px 20px; border-bottom: 1px solid var(--line); cursor: pointer;
  transition: background-color 90ms linear;
}
.skill:hover { background: var(--rack); }
.skill.gone { display: none; }
.skill .nm {
  direction: ltr; unicode-bidi: isolate; text-align: right;
  color: var(--peach); font-weight: 700; font-size: 12.5px; overflow-wrap: anywhere;
}
.skill:hover .nm { color: var(--flesh); }
.skill .kd { font-size: 10px; color: var(--faint); letter-spacing: .1em; }
.skill .hn {
  color: var(--dim); font-size: 12px; unicode-bidi: plaintext; text-align: start;
  display: -webkit-box; -webkit-line-clamp: 1; -webkit-box-orient: vertical; overflow: hidden;
}
.skill.open .hn { -webkit-line-clamp: unset; color: var(--text); }

/* ---------- סוכני־הרקע ---------- */
.crew {
  display: grid; grid-template-columns: 11ch 1fr auto;
  grid-template-areas: "lamp task tail" "lamp from from";
  gap: 4px 14px; padding: 10px 20px; border-bottom: 1px solid var(--line);
  cursor: pointer; transition: background-color 90ms linear;
}
.crew:hover { background: var(--rack); }
.crew .lamp { grid-area: lamp; align-self: start; }
.crew.run .bulb { background: var(--run); }
.crew.quiet .bulb { background: transparent; box-shadow: inset 0 0 0 1px var(--idle); }
.crew.run .state { color: var(--run); }
.crew.quiet .state { color: var(--idle); }
/* משימות מגיעות בעברית ובאנגלית בערבוביה. plaintext קובע כיוון לפי
   האות הראשונה, ולכן משפט אנגלי לא נקטע מהצד ההפוך. */
.crew .task {
  grid-area: task; font-size: 13px;
  unicode-bidi: plaintext; text-align: start; overflow-wrap: anywhere;
}
.crew.quiet .task { color: var(--dim); }
.crew .tail {
  grid-area: tail; display: flex; gap: 12px; align-items: baseline;
  font-size: 12px; color: var(--dim); white-space: nowrap;
}
.crew .from {
  grid-area: from; font-size: 11px; color: var(--faint);
  display: flex; gap: 10px; align-items: baseline; flex-wrap: wrap;
  unicode-bidi: plaintext;
}
.crew .type { direction: ltr; unicode-bidi: isolate; color: var(--dim); }

/* ---------- חיפוש ---------- */
#find {
  flex: 1; background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); outline: none;
  padding: 7px 10px; font-size: 14px;
}
#find:focus { border-color: var(--dim); }
#find::placeholder { color: var(--faint); }
#findcount { flex: none; font-size: 12px; color: var(--dim); white-space: nowrap; }
/* תוצאה = שיחה אחת, עם שם. לא ערימת ציטוטים בלי הקשר. */
.smartbox { margin: 0 0 14px 0; padding-bottom: 8px; border-bottom: 1px solid var(--edge); }
.smarthead { display: flex; gap: 8px; align-items: center; font-size: 12px; color: var(--peach); padding: 4px 20px 8px 20px; }
.smartnote { font-size: 12px; color: var(--dim); padding: 2px 20px 8px 20px; }
.hitwhy { font-size: 12.5px; color: var(--text); padding: 2px 0 4px 0; unicode-bidi: plaintext; }
.hitchat .hitresume { opacity: 1; margin-inline-start: 0; color: var(--peach); cursor: pointer;
  border: 1px solid var(--pit); padding: 1px 8px; }
.hitchat .hitresume:hover { color: var(--flesh); }
.meta .chain { color: var(--peach); }
.hitchat {
  border-bottom: 1px solid var(--line); padding: 12px 20px 13px 20px;
  cursor: pointer; transition: background-color 90ms linear;
}
.hitchat:hover { background: var(--rack); }
.hithead { display: flex; gap: 12px; align-items: baseline; margin-bottom: 7px; }
.hitname {
  font-size: 14px; font-weight: 700; color: var(--text);
  unicode-bidi: plaintext; text-align: right;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.hitchat:hover .hitname { color: var(--peach); }
.hitproj { flex: none; font-size: 11px; color: var(--peach); unicode-bidi: plaintext; }
.hitwhen { flex: none; font-size: 11px; color: var(--faint);
           direction: ltr; unicode-bidi: isolate; }
.hitopen { margin-inline-start: auto; flex: none; font-size: 11px; color: var(--faint);
           opacity: 0; transition: opacity 90ms linear; }
.hitchat:hover .hitopen { opacity: 1; }
.hitline {
  display: flex; gap: 10px; align-items: baseline;
  font-size: 12.5px; padding: 2px 0;
}
.hitwho { flex: none; width: 6ch; font-size: 11px; color: var(--faint); }
.hitline.you .hitwho { color: var(--wait); }
.hittext { color: var(--dim); overflow-wrap: anywhere;
           overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.hitline mark { background: transparent; color: var(--run); font-weight: 700; }
.hitmore { font-size: 11px; color: var(--faint); margin-top: 4px; padding-inline-start: calc(6ch + 10px); }

/* ---------- שיחה ---------- */
#chatslot { direction: ltr; unicode-bidi: isolate; font-size: 17px; font-weight: 700; }
#chattitle {
  font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  cursor: text; padding: 1px 6px; margin: -1px -6px;
  border: 1px solid transparent; outline: none;
}
#chattitle:hover { border-color: var(--edge); }
#chattitle:focus { border-color: var(--peach); cursor: text; overflow: visible; }
#chatmeta { margin-inline-start: auto; display: flex; gap: 12px;
            align-items: baseline; font-size: 12px; color: var(--dim); white-space: nowrap; }
#modelpick {
  -webkit-appearance: none; appearance: none;
  background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); padding: 2px 8px;
  font-size: 12px; outline: none; cursor: pointer;
}
#modelpick:hover { border-color: var(--dim); }

#chatbody { flex: 1; display: flex; min-height: 0; position: relative; }
/* Scroll position is held by the page's own anchor (see "Reading position"),
   so the engine's built-in anchoring is switched off to keep the two from fighting. */
#logscroll { flex: 1; min-width: 0; overflow-anchor: none; }
/* "New messages" pill: shown when something arrives while you read higher up. */
#newpill {
  position: absolute; bottom: 14px; left: 50%; transform: translateX(-50%);
  display: none; z-index: 5; cursor: pointer; white-space: nowrap;
  background: var(--rack); color: var(--peach); border: 1px solid var(--peach);
  padding: 4px 14px; font-size: 12px; border-radius: 14px;
}
#newpill.on { display: block; }
/* In-conversation search: every occurrence marked, the current one stronger.
   ⛔ No padding, no isolation on the mark: it must stay a plain inline run so
   the bidi order of the sentence around it is exactly what it was. */
mark.fhit { background: rgba(242, 163, 101, 0.28); color: inherit; border-radius: 2px; }
mark.fhit.now { background: var(--peach); color: #0a0b0c; }
#chatfind {
  position: absolute; top: 8px; left: 50%; transform: translateX(-50%);
  display: none; z-index: 6; white-space: nowrap; align-items: center; gap: 8px;
  background: var(--rack); color: var(--text); border: 1px solid var(--peach);
  padding: 3px 6px 3px 12px; font-size: 12px; border-radius: 14px;
}
#chatfind.on { display: flex; }
#chatfind .fq { color: var(--peach); unicode-bidi: isolate; max-width: 220px; overflow: hidden; text-overflow: ellipsis; }
#chatfind .fn { color: var(--dim); unicode-bidi: isolate; }
#chatfind .fb { cursor: pointer; padding: 0 6px; color: var(--dim); border-radius: 8px; }
#chatfind .fb:hover { color: var(--text); background: var(--line); }
.hitline { cursor: pointer; }
.hitline:hover { background: var(--line); }
#newpill:hover { background: #1b1f22; }
#log {
  padding: 18px 20px 26px 20px; min-height: 100%;
  display: flex; flex-direction: column; justify-content: flex-end;
}
.turn { margin-bottom: 20px; }
.who {
  font-size: 10px; letter-spacing: 0.14em; color: var(--faint);
  margin-bottom: 4px; display: flex; gap: 10px; align-items: baseline;
}
.when { color: var(--faint); font-size: 10px; }
.body { overflow-wrap: anywhere; }
.turn.you .who { color: var(--wait); }
.turn.you.flash .body {
  border-inline-start-color: var(--peach);
  background: rgba(242,163,101,0.07);
}
.turn.you .body {
  border-inline-start: 2px solid var(--edge);
  transition: background-color 260ms linear, border-color 260ms linear;
  padding-inline-start: 12px; color: #eceee9;
}
.turn.you.pending .body { color: var(--dim); }
.act {
  display: flex; gap: 9px; align-items: baseline;
  color: var(--dim); font-size: 12px; line-height: 1.35; margin-bottom: 2px;
}
.act .tick { width: 6px; height: 6px; flex: none; align-self: center; background: var(--faint); }
.act .what { flex: none; }
.act .arg {
  direction: ltr; unicode-bidi: isolate; text-align: right;
  color: var(--faint);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}

/* ---------- Collapsed view (requested 21.10) ----------
   Each of the user's messages is a header line; everything that follows it —
   the terminal's replies, tool lines — is its answer, folded beneath it.
   The log stays flat (the reading-position anchor walks #log's children),
   so folding is per-block classes: .fo hides an answer block, .open marks
   an expanded request. Off by default; the expanded view is untouched. */
#foldbtn.on { color: var(--peach); border-color: var(--peach); }
.turn .gist, .turn .foldsum, .foldhead { display: none; }
#log.fold .fo { display: none; }
#log.fold .turn.you { margin-bottom: 8px; cursor: pointer; }
#log.fold .turn.you .who { margin-bottom: 2px; }
#log.fold .turn.you .foldsum {
  display: inline; color: var(--faint); letter-spacing: 0; font-size: 11px;
  margin-inline-start: auto; white-space: nowrap;
}
#log.fold .turn.you:hover .foldsum, #log.fold .turn.you.open .foldsum { color: var(--peach); }
#log.fold .turn.you:not(.open) .body { display: none; }
#log.fold .turn.you:not(.open) .gist {
  display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2;
  overflow: hidden; overflow-wrap: anywhere; unicode-bidi: plaintext;
  border-inline-start: 2px solid var(--edge); padding-inline-start: 12px;
  color: #eceee9;
}
#log.fold .turn.you:not(.open):hover .gist { border-inline-start-color: var(--peach); }
#log.fold .turn.you.open { margin-top: 12px; margin-bottom: 14px; }
#log.fold .turn.you.open .body { border-inline-start-color: var(--peach); }
#log.fold .foldhead {
  display: flex; gap: 10px; align-items: baseline; cursor: pointer;
  font-size: 11px; color: var(--faint); margin-bottom: 8px;
}
#log.fold .foldhead:hover { color: var(--peach); }

/* ---------- מרקדאון ---------- */
.md { white-space: normal; }
.md p { margin: 0 0 0.7em 0; white-space: pre-wrap; }
.md p:last-child { margin-bottom: 0; }
.md h1, .md h2, .md h3, .md h4 {
  margin: 1.1em 0 0.45em 0; line-height: 1.3; font-weight: 700; color: #f2f4ef;
}
.md h1 { font-size: 1.42em; }
.md h2 { font-size: 1.22em; }
.md h3 { font-size: 1.08em; }
.md h4 { font-size: 1em; color: var(--peach); }
.md h1:first-child, .md h2:first-child, .md h3:first-child { margin-top: 0; }
.md b { font-weight: 700; color: #f2f4ef; }
.md i { font-style: normal; color: var(--peach); }
.md code {
  background: var(--rack); padding: 0 4px; color: #cfe8d8;
  direction: ltr; unicode-bidi: isolate;
}
.md pre {
  background: var(--rack); border-inline-start: 2px solid var(--edge);
  padding: 9px 12px; margin: 0 0 0.8em 0; overflow-x: auto;
  direction: ltr; text-align: left; unicode-bidi: isolate;
  font-size: 12px; color: #cfe8d8; white-space: pre;
}
.md ul, .md ol { margin: 0 0 0.75em 0; padding-inline-start: 1.5em; }
.md li { margin-bottom: 0.25em; }
.md li.sub { margin-inline-start: 1.4em; }
.md li > ul, .md li > ol { margin: 0.25em 0 0 0; }
.md li > span.lit { unicode-bidi: isolate; }
.md li[dir=rtl] { text-align: right; }
.md li[dir=ltr] { text-align: left; }
.md h5, .md h6 { font-size: 0.95em; color: var(--dim); margin: 1em 0 0.4em 0; }
.md del { color: var(--faint); }
.md bdi.ltr { unicode-bidi: isolate; }
.md img.mdimg { max-width: 100%; max-height: 60vh; width: auto; height: auto; display: block; margin: 0.4em 0; border-radius: 4px; }
.md pre.hl .t-k { color: var(--peach); }
.md pre.hl .t-s { color: #9fd4a8; }
.md pre.hl .t-c { color: var(--faint); }
.md pre.hl .t-n { color: #e6c07b; }
.md blockquote > :last-child { margin-bottom: 0; }
/* Blocks carry their own dir (blockDirs); alignment follows it. */
.md p, .md li, .md h1, .md h2, .md h3, .md h4, .md blockquote { text-align: start; }
.md blockquote {
  margin: 0 0 0.8em 0; padding-inline-start: 12px;
  border-inline-start: 2px solid var(--peach); color: var(--dim);
}
.md hr { border: 0; border-top: 1px solid var(--edge); margin: 1.1em 0; }
.md table { border-collapse: collapse; margin: 0 0 0.9em 0; width: 100%; }
.md th, .md td {
  border: 1px solid var(--line); padding: 5px 9px;
  text-align: start; vertical-align: top; font-size: 12px;
}
.md th { color: #f2f4ef; background: var(--rack); font-weight: 700; }
.md a { color: var(--run); cursor: pointer; text-decoration: none; border-bottom: 1px solid var(--edge); }
.md a:hover { border-bottom-color: var(--run); }
.md a.file { direction: ltr; unicode-bidi: isolate; }
a.url {
  color: var(--run); cursor: pointer; text-decoration: none;
  direction: ltr; unicode-bidi: isolate;
}
a.url:hover { text-decoration: underline; }
.md a.codelink { background: var(--rack); padding: 0 4px; }

/* ── שאלה שנשאלה במסוף ─────────────────────────────────────────────── */
.unit.ask .slot { color: var(--peach); }
.unit.ask .bulb { background: var(--peach); }
.unit.ask .state { color: var(--peach); }
.unit.ask .age { color: var(--text); }
.unit .asking { color: var(--peach); }
.stat.ask .n { color: var(--peach); }
.askcard {
  border: 1px solid var(--peach); background: var(--rack);
  padding: 12px 14px; margin: 14px 0 6px 0;
}
.askcardhead {
  display: flex; gap: 10px; align-items: baseline;
  font-size: 11px; color: var(--peach); margin-bottom: 9px;
}
.askcardhead .asksince { color: var(--faint); }
.askcardhead .askwhere {
  color: var(--dim); margin-inline-start: auto;
  display: inline-flex; gap: 8px; align-items: baseline;
}
.askcardhead .askslot { direction: ltr; unicode-bidi: isolate; color: var(--dim); }
.askcontext { font-size: 13px; line-height: 1.6; color: var(--dim); margin: 8px 0 2px 0; padding-inline-start: 10px; border-inline-start: 2px solid var(--line, #333); }
.askq { font-size: 13px; color: #f2f4ef; margin: 10px 0 7px 0; font-weight: 700; }
.askq.later { color: var(--dim); font-weight: 400; }
.askmulti { font-size: 11px; color: var(--faint); margin-bottom: 6px; }
.askopts { display: flex; flex-direction: column; gap: 6px; }
.askcard button.opt {
  display: block; width: 100%; text-align: right; cursor: pointer;
  font: inherit; font-size: 12px; color: var(--text);
  background: transparent; border: 1px solid var(--line);
  padding: 7px 10px;
}
.askown { width: 100%; resize: vertical; background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); outline: none; padding: 8px 10px; font-size: 13px;
  line-height: 1.5; margin: 6px 0; unicode-bidi: plaintext; }
.askown:focus { border-color: var(--peach); }
.askcard button.opt.off { opacity: .45; cursor: default; }
.askcard button.opt:hover { border-color: var(--peach); color: #f2f4ef; }
.askcard button.opt.sent { border-color: var(--run); color: var(--run); }
.askcard .optlabel { display: block; }
.askcard .optdetail { display: block; margin-top: 3px; font-size: 11px; color: var(--dim); }
/* Each label, question and plan block runs in its own direction (dir=auto);
   start-alignment follows it, so English sits left and Hebrew right. */
.askcard .optlabel[dir], .askcard .optdetail[dir], .askq[dir],
.askplan p, .askplan li, .askplan h1, .askplan h2, .askplan h3, .askplan h4 { text-align: start; }
/* The plan scrolls, and a scroll box clips what sits outside it: with the
   default indent, a left-to-right list lost its numbers to the left edge. */
.askplan ol, .askplan ul { padding-inline-start: 2.6em; }
.askfree { margin-top: 9px; }
.askcard button.opt.other { color: var(--dim); border-style: dashed; }
.askcard button.opt.other:hover { color: var(--peach); }
.askplan { max-height: 260px; overflow-y: auto; margin-bottom: 4px; }
.livehead {
  font-size: 11px; color: var(--peach); margin: 0 0 8px 0;
}
.md .task { color: var(--wait); }
.md .done { color: var(--run); }


/* ---------- כרטיס־קובץ בתוך השיחה ---------- */
.chip {
  display: inline-flex; align-items: baseline; gap: 5px;
  border: 1px solid var(--edge); padding: 0 6px; cursor: pointer;
  color: var(--run); direction: ltr; unicode-bidi: isolate;
  transition: border-color 90ms linear, color 90ms linear;
}
.chip:hover { border-color: var(--run); }
.chip.on { color: var(--peach); border-color: var(--peach); }
.chip .cx { font-size: 10px; color: var(--faint); }

.card {
  border: 1px solid var(--edge); background: var(--rack);
  margin: 6px 0 10px 0;
}
.cardbar {
  display: flex; align-items: center; gap: 10px;
  padding: 5px 10px; border-bottom: 1px solid var(--line); cursor: pointer;
}
.card.shut .cardbar { border-bottom: 0; }
.cardname {
  flex: 1; min-width: 0; font-size: 12px; color: var(--text);
  direction: ltr; unicode-bidi: isolate; text-align: left;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.cardkind { flex: none; font-size: 10px; color: var(--faint); letter-spacing: 0.08em; }
.cardnote { flex: none; font-size: 11px; color: var(--run); }
.cardnote.warn { color: var(--wait); }
.cardbtns { flex: none; display: flex; gap: 6px; }
.cardbtn {
  font-size: 11px; color: var(--dim); border: 1px solid var(--edge);
  padding: 1px 8px; cursor: pointer;
  transition: color 90ms linear, border-color 90ms linear;
}
.cardbtn:hover { color: var(--text); border-color: var(--dim); }
.cardbody { padding: 12px 14px; max-height: 34em; overflow-y: auto; }
.card.shut .cardbody { display: none; }
.cardbody::-webkit-scrollbar { width: 8px; }
.cardbody::-webkit-scrollbar-thumb { background: var(--edge); }
.cardedit {
  width: 100%; min-height: 16em; resize: vertical;
  background: var(--ground); color: var(--text);
  border: 1px solid var(--edge); outline: none; padding: 10px;
  font-size: 12px; line-height: 1.6; direction: rtl; text-align: right;
}
.cardedit:focus { border-color: var(--dim); }
.cardcm { height: 24em; resize: vertical; overflow: hidden; border: 1px solid var(--edge); }
.cardimg {
  display: block; max-width: 100%; max-height: 26em;
  cursor: zoom-in; background: var(--ground);
}
.cardimg.full { max-height: none; cursor: zoom-out; }
.cardraw {
  margin: 0; white-space: pre; overflow-x: auto; font-size: 12px;
  direction: ltr; text-align: left; unicode-bidi: isolate; color: #cfe8d8;
}
.cardmiss { color: var(--wait); font-size: 12px; }

/* ---------- לוח־המסמך ---------- */
#docpane {
  flex: 0 0 46%; min-width: 0; display: none;
  /* הקו מפריד בין המסמך לשיחה. בעברית זה הצד ההתחלתי — הצד הימני של הלוח */
  flex-direction: column; border-inline-start: 1px solid var(--edge);
}
#docpane.on { display: flex; }
#outs { display: none; flex: none; max-height: 46%; overflow-y: auto;
  padding: 8px 0 4px 0; border-bottom: 1px solid var(--edge); background: var(--ground); }
#outs.on { display: block; }
#outsbtn.on { color: var(--peach); border-color: var(--pit); }
#chatview.reader #newpill { display: none; }
#chatview.reader #chatbar, #chatview.reader #alerts, #chatview.reader #logscroll,
#chatview.reader #crewstrip, #chatview.reader #composer, #chatview.reader #outs { display: none; }
#chatview.reader #docpane { flex: 1 1 auto; border-inline-start: 0; }
#chatview.reader #docbar { padding-top: 34px; }
#chatview.reader #docview { max-width: 860px; margin: 0 auto; padding: 22px 28px 60px 28px;
  font-size: 15px; line-height: 1.75; }
#chatview.reader #docedit { font-size: 14px; padding: 22px 28px; }
/* The reader stays monospace (the user, 30.10: the proportional face of 0.36
   went back). Cascadia Mono as installed here carries Hebrew; where it is
   missing, Menlo takes Latin and Courier New, which ships with macOS and is
   fixed-pitch with Hebrew, takes Hebrew instead of a proportional fallback. */
#docview, #docview * { font-family: 'Cascadia Mono', Menlo, 'Courier New', monospace; }
#docbar {
  flex: none; display: flex; align-items: center; gap: 10px;
  padding: 9px 16px; border-bottom: 1px solid var(--line); background: var(--ground);
}
#docname {
  flex: 1; min-width: 0; font-size: 12px; color: var(--dim);
  direction: ltr; unicode-bidi: isolate; text-align: left;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
#docnote { flex: none; font-size: 11px; color: var(--run); }
#docnote.warn { color: var(--wait); }
#docscroll { flex: 1; overflow-y: auto; }
#docview { padding: 16px 18px 30px 18px; }
#docedit {
  width: 100%; height: 100%; resize: none;
  background: var(--ground); color: var(--text);
  border: 0; outline: none; padding: 16px 18px;
  font-size: 13px; line-height: 1.6; display: none;
  unicode-bidi: plaintext; text-align: start;
}
#docedit.on { display: block; }
#doccm { display: none; height: 100%; }
#doccm.on { display: block; }
#docscroll.editing { padding: 0; }

/* ---------- שורת־ההקלדה ---------- */
#composer {
  flex: none; border-top: 1px solid var(--edge);
  background: var(--ground); padding: 9px 20px 14px 20px;
}
#target {
  font-size: 11px; color: var(--faint); margin-bottom: 6px;
  display: flex; gap: 10px; align-items: baseline;
}
#field {
  width: 100%; resize: none; min-height: 2.6em; max-height: 9em;
  background: var(--rack); color: var(--text);
  border: 1px solid var(--edge); outline: none;
  padding: 8px 10px; font-size: 13px; line-height: 1.5;
}
#field:focus { border-color: var(--dim); }
#field::placeholder { color: var(--faint); }
/* The predicted next message, as ghost text in the empty field */
#field.ghost::placeholder { color: var(--dim); }
#gtake { display: none; color: var(--peach); cursor: pointer; margin-inline-end: 10px; }
#gtake.on { display: inline; }
#gtake:hover { text-decoration: underline; }
#keys { margin-top: 5px; font-size: 11px; color: var(--faint); }
#clip {
  display: none; gap: 8px; flex-wrap: wrap; margin-bottom: 7px;
}
#clip.on { display: flex; }
.clipped {
  display: flex; gap: 7px; align-items: center;
  border: 1px solid var(--edge); padding: 3px 8px; font-size: 11px; color: var(--peach);
  cursor: pointer; transition: border-color 90ms linear;
}
.clipped:hover { border-color: var(--peach); }
.clipped img {
  width: 34px; height: 34px; object-fit: cover; display: block;
  background: var(--ground); flex: none;
}
.clipped span { direction: ltr; unicode-bidi: isolate; }
.clipped u { text-decoration: none; color: var(--faint); cursor: pointer; }
.clipped u:hover { color: var(--wait); }
/* המסך כולו הופך למטרה בזמן גרירה — לא ריבוע קטן שצריך לכוון אליו */
#drop {
  position: fixed; inset: 0; z-index: 40; display: none;
  align-items: center; justify-content: center;
  background: rgba(10,11,12,.86); box-shadow: inset 0 0 0 2px var(--peach);
}
#drop.on { display: flex; }
#drop b { font-size: 16px; color: var(--peach); }

/* חלונית־השחזור. ⛔ אינה `view` ואינה במערכת־המצבים: מצב חדש היה מחייב
   להשחיל ערך דרך scan, הסגירה האסינכרונית וחתימת paint — שינוי בצנרת
   הציור בשביל תוספת אחת. */
#restorewrap {
  position: fixed; inset: 0; z-index: 45; display: none;
  align-items: center; justify-content: center; background: rgba(10,11,12,.86);
}
#restorewrap.on { display: flex; }
#restorebox {
  width: min(680px, 88vw); max-height: 78vh; display: flex; flex-direction: column;
  background: var(--rack); border: 1px solid var(--edge);
}
#restorehead, #restorefoot {
  display: flex; gap: 12px; align-items: center;
  padding: 10px 14px; border-bottom: 1px solid var(--line);
}
#restorefoot { border-bottom: 0; border-top: 1px solid var(--line); }
#restorehead b { color: var(--peach); font-size: 13px; }
#restorehead /* ⛔ **בורר גלובלי בתוך תוספת מקומית.** הכלל הזה נכתב כדי לדחוף כפתור
   אחד לקצה בכף־הרגל של חלון־השחזור, ונכתב כ-`.btn` — כלומר הוא חל על
   **כל** כפתור באפליקציה. בכותרת־המדף, שהיא שורת־פלקס, שוליים־אוטומטיים
   על הכפתור הראשון דוחפים את כל מה שאחריו אל מחוץ לרוחב, והכותרת כולה
   נעלמת מהמסך. נמדד על צילום של המשתמש: המדף נפתח בלי שורת־הכותרת כלל.
   ⇒ בורר של תוספת חייב להיות מתוחם לתוספת. */
#restorefoot .btn { margin-inline-start: auto; }
#restorefoot #rsnote { color: var(--dim); font-size: 11px; }
#restorelist { overflow-y: auto; padding: 4px 0; }
.rsrow {
  display: flex; gap: 10px; align-items: baseline;
  padding: 7px 14px; border-bottom: 1px solid var(--line); cursor: pointer;
}
.rsrow:hover { background: var(--ground); }
.rsrow input { accent-color: var(--peach); }
/* ⚠ הכותרת היא טקסט עברי והנתיב לטיני. בלי בידוד הם מתערבבים בשורה. */
.rstitle { flex: 1; color: var(--text); font-size: 12px; unicode-bidi: isolate; }
.rsmeta  { color: var(--faint); font-size: 11px; direction: ltr; unicode-bidi: isolate; }
.rsempty { padding: 18px 14px; color: var(--dim); font-size: 12px; }
#composer.off #field { opacity: 0.4; pointer-events: none; }

/* לוח־הפקודות */
#palette {
  display: none; border: 1px solid var(--edge); border-bottom: 0;
  background: var(--rack); max-height: 15em; overflow-y: auto;
}
#palette.on { display: block; }
.cmd {
  display: flex; gap: 10px; align-items: baseline;
  padding: 5px 10px; cursor: pointer; border-bottom: 1px solid var(--line);
}
.cmd:last-child { border-bottom: 0; }
.cmd.pick { background: var(--ground); }
.cmd .nm {
  flex: none; color: var(--peach); font-weight: 700; font-size: 12px;
  direction: ltr; unicode-bidi: isolate;
}
.cmd.pick .nm { color: var(--run); }
.cmd .kd { flex: none; font-size: 10px; color: var(--faint); letter-spacing: 0.08em; }
.cmd .hn {
  flex: 1; min-width: 0; font-size: 11px; color: var(--dim);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.cmd .pk { flex: none; font-size: 10px; color: var(--wait); }
</style>
</head>
<body>
<div id="grain"></div>
<div id="restorewrap">
  <div id="restorebox">
    <div id="restorehead">
      <b>\(Lang.t("שחזור שיחות", "Restore sessions"))</b>
      <span class="btn" id="rsclose">\(Lang.t("סגירה", "Close"))</span>
    </div>
    <div id="restorelist"></div>
    <div id="restorefoot">
      <span id="rsnote"></span>
      <span class="btn" id="rsgo">\(Lang.t("החזר למסך", "Reopen"))</span>
    </div>
  </div>
</div>

<div id="drop"><b>\(Lang.t("שחרר כאן — הקובץ יצורף לשורה", "Drop here — the file attaches to the line"))</b></div>


<div class="view on" id="rackview">
  <header>
    <span id="logo" title="\(Lang.t("לסדר את המדף מחדש — עובדים למעלה", "Re-sort the rack — working on top"))"></span>
    <span id="name">\(Lang.t("פיץ׳", "Peach"))</span>
    <span class="btn" id="findbtn">\(Lang.t("חיפוש", "Search"))</span>
    <span class="btn" id="asksbtn">\(Lang.t("שאלות", "Questions"))</span>
    <span class="btn" id="spendbtn">\(Lang.t("צריכה", "Usage"))</span>
    <span class="btn" id="newterm" title="\(Lang.t("מסוף חדש — האישור נמסר בחלון שנפתח", "New terminal — approve it in the window that opens"))">\(Lang.t("+ מסוף", "+ terminal"))</span>
    <span class="btn" id="restorebtn" title="\(Lang.t("מחזיר למסך שיחות שנסגרו — בוחרים אילו", "Reopen closed sessions — you pick which"))">\(Lang.t("שחזור", "Restore"))</span>
    <span class="btn off" id="wakeall" title="\(Lang.t("שולח ״תמשיך״ לכל מי שממתין לך", "Sends continue to everyone waiting for you"))">\(Lang.t("להעיר", "Wake"))</span>
    <div id="readout"></div>
    <span id="clock"></span>
  </header>
  <div id="sift"></div>
  <div class="scroll"><div id="units"></div></div>
</div>

<div id="dial"><span class="digits"></span><span class="what"></span></div>

<div class="view" id="spendview">
  <header>
    <span class="btn" id="spendback">\(Lang.t("→ המדף", "→ Rack"))</span>
    <span id="name">\(Lang.t("צריכה", "Usage"))</span>
    <span class="pill" id="spanday">\(Lang.t("היום", "today"))</span>
    <span class="pill" id="spanweek">\(Lang.t("שבוע", "week"))</span>
    <span class="pill" id="spanall">\(Lang.t("הכול", "All"))</span>
    <div id="readout"><span id="spendstate"></span></div>
  </header>
  <div id="quota"></div>
  <div id="spendhead"></div>
  <div class="scroll"><div id="spendlist"></div></div>
</div>

<div class="view" id="asksview">
  <header>
    <span class="btn" id="asksback">\(Lang.t("→ המדף", "→ Rack"))</span>
    <span id="name">\(Lang.t("שאלות שממתינות לך", "Questions waiting for you"))</span>
    <div id="askscount"></div>
  </header>
  <div class="scroll"><div id="askslist"></div></div>
</div>

<div class="view" id="worksview">
  <div id="worksbar">
    <span class="btn" id="worksback">\(Lang.t("→ המדף", "→ Rack"))</span>
    <input id="worksfind" type="text" placeholder="\(Lang.t("לסנן לפי שם או תיקייה · אנטר פותח את הראשון", "Filter by name or folder · Enter opens the first"))" autocomplete="off">
    <span class="btn" id="worksmart" title="\(Lang.t("מעביר לחיפוש, והמודל מוצא לפי משמעות", "Moves to search, where the model finds by meaning"))">\(Lang.t("לחפש במילים", "Find in words"))</span>
    <span id="workscount"></span>
  </div>
  <div class="sift"><span class="lbl">\(Lang.t("סוג", "Kind"))</span><span id="siftkind"></span></div>
  <div class="sift"><span class="lbl">\(Lang.t("פרויקט", "Project"))</span><span id="siftproj"></span></div>
  <div class="sift"><span class="lbl">\(Lang.t("מתי", "When"))</span><span id="siftwhen"></span></div>
  <div class="scroll"><div id="workslist"></div></div>
</div>

<div class="view" id="bookview">
  <div id="bookbar">
    <span class="btn" id="bookback">\(Lang.t("→ המדף", "→ Rack"))</span>
    <input id="booksift" type="text" placeholder="\(Lang.t("לסנן — שם, סוג, או מילה בתיאור", "Filter — name, kind, or a word in the description"))" autocomplete="off">
    <span id="bookcount"></span>
  </div>
  <div class="scroll"><div id="booklist"></div></div>
</div>

<div class="view" id="crewview">
  <header>
    <span class="btn" id="crewback">\(Lang.t("→ המדף", "→ Rack"))</span>
    <span id="name">\(Lang.t("סוכני־הרקע", "Background agents"))</span>
    <div id="crewcount"></div>
  </header>
  <div class="scroll"><div id="crewlist"></div></div>
</div>

<div class="view" id="searchview">
  <div id="findbar">
    <input id="find" type="text" placeholder="\(Lang.t("שם של קובץ או שיחה, או תיאור במילים · ⌘⌥F מכל מקום", "A file or conversation name, or describe it in words · ⌘⌥F from anywhere"))" autocomplete="off">
    <span class="btn" id="smartgo" title="\(Lang.t("המודל קורא את השיחות והקבצים ומוצא לפי משמעות", "The model reads conversations and files and finds by meaning"))">\(Lang.t("לשאול במילים", "Ask in words"))</span>
    <span id="findcount"></span>
  </div>
  <div class="scroll"><div id="hits"></div></div>
</div>

<div class="view" id="chatview">
  <div id="chatbar">
    <span class="btn" id="back">\(Lang.t("→ המדף", "→ Rack"))</span>
    <span id="chatslot"></span>
    <span id="chattitle"></span>
    <span id="chatmeta"></span>
    <select id="modelpick"></select>
    <span class="btn" id="foldbtn" title="\(Lang.t("תצוגה מקופלת — רק הבקשות שלך, התשובות מקופלות מתחתן", "Collapsed view — only your requests, answers folded beneath them")) · \u{21E7}\u{2318}C">\(Lang.t("מקופל", "Collapsed"))</span>
    <span class="btn" id="mine">\(Lang.t("אחרון שלי", "My last"))</span>
    <span class="btn" id="outsbtn"></span>
    <span class="btn" id="raise">\(Lang.t("לחלון", "To window"))</span>
  </div>
  <div id="alerts"></div>
  <div id="outs"></div>
  <div id="chatbody">
    <div class="scroll" id="logscroll"><div id="log"></div></div>
    <div id="newpill"></div>
    <div id="chatfind"><span class="fq"></span><span class="fn"></span><span class="fb" id="findprev" title="\u{21E7}\u{2318}G">\u{25B2}</span><span class="fb" id="findnext" title="\u{2318}G">\u{25BC}</span><span class="fb" id="findclose" title="Esc">\u{2715}</span></div>
    <div id="docpane">
      <div id="docbar">
        <span id="docname"></span>
        <span id="docnote"></span>
        <span class="btn" id="docmode">\(Lang.t("עריכה", "Edit"))</span>
        <span class="btn" id="docout">\(Lang.t("בדפדפן", "In browser"))</span>
        <span class="btn" id="docclose">\(Lang.t("סגירה", "Close"))</span>
      </div>
      <div class="scroll" id="docscroll">
        <div id="docview" class="md"></div>
        <textarea id="docedit" dir="auto" spellcheck="false"></textarea>
        <div id="doccm"></div>
      </div>
    </div>
  </div>
  <div id="crewstrip"></div>
  <div id="composer">
    <div id="target"></div>
    <div id="clip"></div>
    <div id="palette"></div>
    <textarea id="field" rows="2" placeholder="\(Lang.t("לכתוב אל המסוף…  לוכסן פותח פקודות", "Write to the terminal…  slash opens commands"))"></textarea>
    <div id="keys"><span id="gtake"></span>\(Lang.t("אנטר שולח · שיפט־אנטר שורה חדשה · חץ־למעלה מחזיר מה שאמרת · הדבקה או גרירה מצרפת קובץ", "Enter sends · Shift-Enter new line · Up recalls what you said · paste or drag attaches a file"))</div>
  </div>
</div>
<script>
'use strict';

/* שורה חדשה נבנית מקוד־התו ולא מרצף־בריחה. הדף חי בתוך מחרוזת של סוויפט,
   ולוכסן אחורי בו עובר שתי שכבות פענוח — מקור לשלוש תקלות בעבר. */
var NL = String.fromCharCode(10);

function el(tag, cls, text) {
  var n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = String(text);
  return n;
}

function send(act, extra) {
  var msg = { act: act };
  if (extra) { Object.keys(extra).forEach(function (k) { msg[k] = extra[k]; }); }
  window.webkit.messageHandlers.peach.postMessage(msg);
}

/* ---------- הסמליל ---------- */

var SVGNS = 'http://www.w3.org/2000/svg';

/* בונים את הצורות כאלמנטים אמיתיים ולא כסמל משוכפל: גיליון־הסגנון אינו
   חודר לעץ־הצללים של שכפול, והסמליל יצא ריבוע שחור בלי צבע ובלי קו. */
function svgNode(tag, attrs) {
  var node = document.createElementNS(SVGNS, tag);
  Object.keys(attrs || {}).forEach(function (k) { node.setAttribute(k, attrs[k]); });
  return node;
}

function svgRoot(w, h, viewBox, cls) {
  var svg = svgNode('svg', { width: w, height: h, viewBox: viewBox });
  if (cls) { svg.setAttribute('class', cls); }
  return svg;
}

var PEACH_SKIN = 'M32 10 C46 10 56 21 56 34 C56 47 45 56 32 56 C19 56 8 47 8 34 C8 21 18 10 32 10 Z';
var PEACH_CLEFT = 'M32 11 C25 22 25 45 32 55';
var PEACH_LEAF = 'M32 11 C37 3 47 1 51 3 C49 10 40 14 32 11 Z';
var SET_SHELL = 'M12 6 C36 2 60 2 84 6 C88 26 88 50 84 70 C60 74 36 74 12 70 C8 50 8 26 12 6 Z';
var SET_GLASS = 'M17 11 C37 8 59 8 79 11 C82 27 82 49 79 65 C59 68 37 68 17 65 C14 49 14 27 17 11 Z';

function peachSVG(size) {
  var svg = svgRoot(size, size, '0 0 64 64');
  svg.appendChild(svgNode('path', { d: PEACH_SKIN, 'class': 'skin' }));
  svg.appendChild(svgNode('path', { d: PEACH_CLEFT, 'class': 'cleft' }));
  svg.appendChild(svgNode('path', { d: PEACH_LEAF, 'class': 'leaf' }));
  return svg;
}

/* אפרסק מסתובב לבדו — משמש גם כסמן־טעינה, בכל מקום שבו משהו קורה */
function spinner(size) {
  var box = el('span', 'spin');
  box.style.width = size + 'px';
  box.style.height = size + 'px';
  var fruit = el('span', 'fruit');
  fruit.style.display = 'inline-block';
  fruit.appendChild(peachSVG(size));
  box.appendChild(fruit);
  return box;
}

/* המקלט השלם: מסך, סריקה, ובתוכו האפרסק */
function markNode(w) {
  var h = Math.round(w * 80 / 96);
  var wrap = el('span', 'mark');
  wrap.style.position = 'relative';
  wrap.style.width = w + 'px';
  wrap.style.height = h + 'px';

  var svg = svgRoot(w, h, '0 0 96 80');
  svg.appendChild(svgNode('path', { d: SET_GLASS, 'class': 'glass' }));
  svg.appendChild(svgNode('path', { d: SET_SHELL, 'class': 'set' }));
  svg.appendChild(svgNode('rect', { x: 26, y: 74, width: 12, height: 4, 'class': 'knob' }));
  svg.appendChild(svgNode('rect', { x: 58, y: 74, width: 12, height: 4, 'class': 'knob' }));
  wrap.appendChild(svg);

  var inner = spinner(Math.round(w * 0.42));
  inner.style.position = 'absolute';
  inner.style.left = '50%';
  inner.style.top = '45%';
  inner.style.transform = 'translate(-50%, -50%)';
  wrap.appendChild(inner);

  var scan = svgRoot(w, h, '0 0 96 80');
  scan.style.position = 'absolute';
  scan.style.left = '0';
  scan.style.top = '0';
  scan.style.pointerEvents = 'none';
  scan.appendChild(svgNode('line', { x1: 18, x2: 78, y1: 12, y2: 12, 'class': 'scan' }));
  wrap.appendChild(scan);
  return wrap;
}

/* מהירות הסיבוב היא מדד: כמה מסופים עובדים ברגע זה. אפס — האפרסק עומד. */
function setPace(working) {
  var seconds = working <= 0 ? 0 : Math.max(1.4, 7 - (working - 1) * 1.1);
  document.documentElement.style.setProperty('--spin', seconds + 's');
  var all = document.querySelectorAll('.fruit');
  for (var i = 0; i < all.length; i++) {
    all[i].className = working <= 0 ? 'fruit still' : 'fruit';
  }
}

function stat(kind, n, label) {
  var box = el('div', 'stat ' + kind);
  box.appendChild(el('span', 'n', n));
  box.appendChild(el('span', 'l', label));
  return box;
}

/* ================= מרקדאון ================= */

/* נתיבים שנמצאו בטקסט הנוכחי. הם הופכים לקישור שפותח את המסמך. */
var livePaths = [];

function leaf(text, frag) {
  if (!text) { return; }
  var rest = text;
  var guard = 0;
  while (guard < 40) {
    guard++;
    var best = -1, hitPath = '';
    for (var i = 0; i < livePaths.length; i++) {
      var at = rest.indexOf(livePaths[i]);
      if (at >= 0 && (best < 0 || at < best)) { best = at; hitPath = livePaths[i]; }
    }
    if (best < 0) { break; }
    if (best > 0) { frag.appendChild(document.createTextNode(rest.slice(0, best))); }
    frag.appendChild(chipFor(hitPath));
    rest = rest.slice(best + hitPath.length);
  }
  if (rest) { ltrRuns(rest, frag); }
}

/* A path inside a right-to-left sentence was drawn scrambled: its Hebrew
   segments joined the sentence and the slashes flipped (measured 30.10 on
   ~/Documents/claude/questions.md inside a Hebrew paragraph). Path-like
   words are isolated as their own left-to-right run. */
function isPathish(w) {
  if (w.length < 3 || w.indexOf(NL) >= 0 || w.indexOf('/') < 0) { return false; }
  var c = w.charAt(0);
  if (c === '~' || c === '/' || w.slice(0, 2) === './' || w.slice(0, 3) === '../') { return true; }
  return /[A-Za-z]/.test(c);
}

function ltrRuns(text, frag) {
  var out = '';
  String(text).split(' ').forEach(function (w, i) {
    if (i > 0) { out += ' '; }
    var core = w, tail = '';
    while (core.length && '.,;:!?)'.indexOf(core.charAt(core.length - 1)) >= 0) {
      tail = core.charAt(core.length - 1) + tail;
      core = core.slice(0, -1);
    }
    if (!isPathish(core)) { out += w; return; }
    if (out) { frag.appendChild(document.createTextNode(out)); out = ''; }
    var b = el('bdi', 'ltr', core);
    b.dir = 'ltr';
    frag.appendChild(b);
    out = tail;
  });
  if (out) { frag.appendChild(document.createTextNode(out)); }
}

function italic(text, frag) {
  var parts = String(text).split('*');
  parts.forEach(function (part, i) {
    if (!part) { return; }
    if (i % 2 === 1) { frag.appendChild(el('i', null, part)); }
    else { leaf(part, frag); }
  });
}

function bold(text, frag) {
  var parts = String(text).split('**');
  parts.forEach(function (part, i) {
    if (!part) { return; }
    if (i % 2 === 1) { frag.appendChild(el('b', null, part)); }
    else { italic(part, frag); }
  });
}

function strike(text, frag) {
  var parts = String(text).split('~~');
  parts.forEach(function (part, i) {
    if (!part) { return; }
    if (i % 2 === 1 && i < parts.length - 1) {
      var d = el('del');
      bold(part, d);
      frag.appendChild(d);
    } else { bold(i % 2 === 1 ? '~~' + part : part, frag); }
  });
}

/* ── כתובת־רשת חשופה ──────────────────────────────────────────────────
   בלי ביטוי־רגולרי בכוונה: כל הקובץ הזה הוא מחרוזת־סוויפט, ולוכסן־הפוך
   בתוכה הוא רצף־בריחה של סוויפט ולא של הדפדפן. סריקה ידנית עוקפת את זה. */
var URLHEADS = ['https://', 'http://', 'www.'];

function urlStops(ch) {
  return ch <= ' ' || '<>"`()[]{}|'.indexOf(ch) >= 0 || ch === "'";
}

function findURL(text, from) {
  var pos = from || 0;
  var guard = 0;
  while (guard < 400) {
    guard++;
    var best = -1, head = '';
    for (var k = 0; k < URLHEADS.length; k++) {
      var at = text.indexOf(URLHEADS[k], pos);
      if (at >= 0 && (best < 0 || at < best)) { best = at; head = URLHEADS[k]; }
    }
    if (best < 0) { return null; }
    // כתובת בלי קידומת נחשבת כתובת רק כשהיא פותחת מילה
    if (head === 'www.' && best > 0 && !urlStops(text.charAt(best - 1))) {
      pos = best + 1; continue;
    }
    var end = best;
    while (end < text.length && !urlStops(text.charAt(end))) { end++; }
    var raw = text.slice(best, end);
    // סימן־פיסוק בסוף משפט אינו חלק מהכתובת
    while (raw.length && '.,;:!?'.indexOf(raw.charAt(raw.length - 1)) >= 0) {
      raw = raw.slice(0, -1);
    }
    if (raw.length <= head.length) { pos = best + 1; continue; }
    return { at: best, raw: raw };
  }
  return null;
}

function urlAnchor(raw, cls) {
  var a = el('a', cls || 'url', raw);
  a.dataset.href = raw.indexOf('www.') === 0 ? 'https://' + raw : raw;
  return a;
}

/* טקסט רגיל: כתובת חשופה הופכת לעוגן, השאר ממשיך להדגשה */
function autolink(text, frag) {
  var rest = String(text);
  var guard = 0;
  while (guard < 60) {
    guard++;
    var hit = findURL(rest, 0);
    if (!hit) { break; }
    strike(rest.slice(0, hit.at), frag);
    frag.appendChild(urlAnchor(hit.raw));
    rest = rest.slice(hit.at + hit.raw.length);
  }
  strike(rest, frag);
}

/* גוש־קוד: הטקסט נשאר כמות שהוא, אבל כתובת בתוכו נלחצת */
function preLinked(cls, text) {
  var pre = el('pre', cls || null);
  var rest = String(text);
  var guard = 0;
  while (guard < 400) {
    guard++;
    var hit = findURL(rest, 0);
    if (!hit) { break; }
    pre.appendChild(document.createTextNode(rest.slice(0, hit.at)));
    pre.appendChild(urlAnchor(hit.raw));
    rest = rest.slice(hit.at + hit.raw.length);
  }
  pre.appendChild(document.createTextNode(rest));
  return pre;
}

function links(text, frag) {
  var rest = String(text);
  var guard = 0;
  while (guard < 40) {
    guard++;
    var open = rest.indexOf('[');
    if (open < 0) { break; }
    var mid = rest.indexOf('](', open);
    var close = mid < 0 ? -1 : rest.indexOf(')', mid);
    if (mid < 0 || close < 0) { break; }
    if (open > 0 && rest.charAt(open - 1) === '!') {
      autolink(rest.slice(0, open - 1), frag);
      frag.appendChild(mdImage(rest.slice(open + 1, mid), rest.slice(mid + 2, close).trim()));
      rest = rest.slice(close + 1);
      continue;
    }
    autolink(rest.slice(0, open), frag);
    var a = el('a', null, rest.slice(open + 1, mid));
    a.dataset.href = rest.slice(mid + 2, close);
    frag.appendChild(a);
    rest = rest.slice(close + 1);
  }
  autolink(rest, frag);
}

/* Images by relative path resolve against the document's own folder
   (mdBase, set by the reader). The page cannot read files, so the bytes
   come through the same asset channel as cards. */
var mdBase = '';
var mdImgWait = {};

function normPath(path) {
  var out = [];
  path.split('/').forEach(function (seg, i) {
    if (seg === '.' || (seg === '' && i > 0)) { return; }
    if (seg === '..' && out.length > 1) { out.pop(); return; }
    out.push(seg);
  });
  return out.join('/');
}

function mdImage(alt, src) {
  var img = el('img', 'mdimg');
  img.alt = alt;
  if (src.indexOf('http') === 0 || src.indexOf('data:') === 0) { img.src = src; return img; }
  var c = src.charAt(0);
  var full = normPath(c === '/' || c === '~' ? src : (mdBase ? mdBase + '/' + src : src));
  if (assets[full] && assets[full].src) { img.src = assets[full].src; return img; }
  (mdImgWait[full] = mdImgWait[full] || []).push(img);
  send('asset', { path: full });
  return img;
}

function inline(text) {
  var frag = document.createDocumentFragment();
  String(text).split('`').forEach(function (chunk, i) {
    if (i % 2 === 1) {
      // נתיב בתוך גרשי־קוד הוא עדיין קובץ. בלי הבדיקה הזאת כל מסירה
      // שנכתבה בפורמט הרגיל — נתיב בגרשיים, שורה לקובץ — לא ייצרה כרטיס.
      var one = chunk.trim();
      var hit = livePaths.indexOf(one) >= 0 ? null : findURL(one, 0);
      if (livePaths.indexOf(one) >= 0) { frag.appendChild(chipFor(one)); }
      else if (hit && hit.at === 0 && hit.raw === one) {
        frag.appendChild(urlAnchor(one, 'url codelink'));
      }
      else { frag.appendChild(el('code', null, chunk)); }
    } else { links(chunk, frag); }
  });
  return frag;
}

function heading(line) {
  var n = 0;
  while (n < line.length && line.charAt(n) === '#') { n++; }
  if (n === 0 || n > 6 || line.charAt(n) !== ' ') { return null; }
  var h = el('h' + n);
  h.appendChild(inline(line.slice(n + 1).trim()));
  return h;
}

function bulletOf(line) {
  var t = line.trim();
  var indent = 0;
  while (indent < line.length && (line.charAt(indent) === ' ' || line.charAt(indent) === '\t')) {
    indent += line.charAt(indent) === ' ' ? 1 : 4;
  }
  var two = t.slice(0, 2);
  if (two === '- ' || two === '* ' || two === '+ ' || two === '· ') {
    return { text: t.slice(2), ordered: false, sub: indent > 0, indent: indent };
  }
  var k = 0;
  while (k < t.length && k < 9 && t.charAt(k) >= '0' && t.charAt(k) <= '9') { k++; }
  if (k > 0 && (t.charAt(k) === '.' || t.charAt(k) === ')') && t.charAt(k + 1) === ' ') {
    return { text: t.slice(k + 2), ordered: true, sub: indent > 0, indent: indent, num: Number(t.slice(0, k)) };
  }
  return null;
}

function tableRow(line) {
  var t = line.trim();
  if (t.charAt(0) !== '|') { return null; }
  var cells = t.split('|');
  cells.shift();
  if (cells.length && cells[cells.length - 1].trim() === '') { cells.pop(); }
  return cells.map(function (c) { return c.trim(); });
}

function isDivider(cells) {
  return cells.every(function (c) {
    return c.length > 0 && c.split('').every(function (ch) {
      return ch === '-' || ch === ':' || ch === ' ';
    });
  });
}

/* ================= כרטיסי־קובץ ================= */

/* מה שנפתח, מה שנערך, ומה נאמר על כל קובץ. נשמר כאן ולא בעץ־המסך, כי
   הציור מחדש בונה את השיחה מאפס וכל מצב שיושב באלמנט היה נמחק. */
var cardState = {};
/* תוכן שהגיע מהצד השני. נשלח פעם אחת לכל קובץ, בפתיחה. */
var assets = {};
/* האלמנטים החיים, לפי נתיב — כדי לרענן כרטיס אחד בלי לצייר הכל. */
var cardNodes = {};
/* הקובץ שנערך ברגע זה. כל עוד הוא קיים, השיחה אינה מצוירת מחדש —
   ציור מחדש היה מוחק טיוטה שלא נשמרה. */
var editingPath = null;
/* נתיבים שהופיעו בבלוק הנוכחי וממתינים לכרטיס מתחתיו. */
var pendingCards = [];
/* כרטיס נוצר רק בגוף השיחה. בלוח הצדדי ובתוך כרטיס אחר הוא היה יוצר
   רישום כפול לאותו נתיב, והרענון היה מגיע לאלמנט שכבר אינו על המסך. */
var cardsEnabled = true;

/* תמונה שנטענת אחרי הציור מגדילה את השיחה כלפי מטה, והתחתית שהייתה
   מול העיניים נדחפת מחוץ למסך. לכן כל שינוי־גובה נעשה עם עוגן־תחתית. */
function nearBottom() {
  var box = document.getElementById('logscroll');
  return box.scrollHeight - box.scrollTop - box.clientHeight < NEAR_BOTTOM;
}

/* ================= Reading position =================
   Reported 8.10: reading a conversation upward, the view jumped down every
   now and then. Causes found:
   - every refresh rebuilds the whole log, and the log is a sliding window of
     the last N turns: a new turn drops one from the top, so an unchanged
     scrollTop lands on later text;
   - images and file cards finish loading after the rebuild and push the text
     that was in view;
   - the rebuild ran on every agent step, not only on new text.
   Rule now: the view follows the bottom ONLY when the reader is already there
   (within NEAR_BOTTOM px). Otherwise the line that was at the top of the view
   stays exactly where it was, whatever is added or resized above or below it,
   and a pill offers the jump down. */
var NEAR_BOTTOM = 80;

/* Follow the bottom or not. Set only from the reader's own position — never
   re-measured after an image grows, which would fake "scrolled up". */
var stickBottom = true;

/* The top of the view, as up to six visible blocks with their offset from the
   top edge. Several, because the window may drop the first one from the top. */
var anchor = null;
var anchorFrame = 0;
/* Where the page itself last put the scroll. A scroll event landing there is
   ours, not the reader's, and does not re-take the anchor — re-taking it after
   every correction would let sub-pixel rounding creep the text along. */
var placedTop = -1;

function captureAnchor() {
  var box = document.getElementById('logscroll');
  var top = box.getBoundingClientRect().top;
  var kids = document.getElementById('log').children;
  var out = [];
  for (var i = 0; i < kids.length && out.length < 6; i++) {
    var k = kids[i];
    if (!k.dataset || !k.dataset.k) { continue; }
    var r = k.getBoundingClientRect();
    if (r.bottom <= top) { continue; }
    var a = { k: k.dataset.k, off: r.top - top, sub: -1, subOff: 0 };
    // A long turn cut by the top edge: hold the paragraph in view, not the
    // turn's head — an image inside the turn above that paragraph moves it.
    if (!out.length && r.top < top) {
      var body = k.querySelector('.body');
      if (body) {
        for (var j = 0; j < body.children.length; j++) {
          var rr = body.children[j].getBoundingClientRect();
          if (rr.bottom > top) { a.sub = j; a.subOff = rr.top - top; break; }
        }
      }
    }
    out.push(a);
  }
  anchor = out.length ? out : null;
}

function restoreAnchor() {
  if (!anchor) { return false; }
  var box = document.getElementById('logscroll');
  var top = box.getBoundingClientRect().top;
  var byKey = {};
  var kids = document.getElementById('log').children;
  for (var i = 0; i < kids.length; i++) {
    if (kids[i].dataset && kids[i].dataset.k) { byKey[kids[i].dataset.k] = kids[i]; }
  }
  for (var n = 0; n < anchor.length; n++) {
    var a = anchor[n];
    var node = byKey[a.k];
    // A block folded away (collapsed view) has no position to hold.
    if (!node || node.offsetParent === null) { continue; }
    var target = node, want = a.off;
    if (a.sub >= 0) {
      var body = node.querySelector('.body');
      if (body && body.children[a.sub]) { target = body.children[a.sub]; want = a.subOff; }
    }
    var delta = Math.round(target.getBoundingClientRect().top - top - want);
    if (delta !== 0) { box.scrollTop = box.scrollTop + delta; placedTop = box.scrollTop; }
    return true;
  }
  return false;
}

/* After anything changes size: stay at the bottom if following it, otherwise
   hold the reading line. */
function settle() {
  if (stickBottom) { toBottom(); } else { restoreAnchor(); }
}

document.getElementById('logscroll').addEventListener('scroll', function () {
  // ⛔ ‏`toBottom` על יומן קצר מציב את הגלילה על אפס, וזה נראה בדיוק כמו
  //    "גללתי עד הראש" — כלומר טעינה אוטומטית שאיש לא ביקש, בכל שיחה קצרה.
  //    ⇒ נטען רק כשיש באמת לאן לגלול.
  var bar = document.getElementById('earlier');
  if (bar && bar.className !== 'done' && this.scrollTop < 40
      && this.scrollHeight - this.clientHeight > 300) { askEarlier(); }
  stickBottom = nearBottom();
  if (stickBottom) { hidePill(); }
  if (Math.abs(this.scrollTop - placedTop) < 1) { return; }
  placedTop = -1;
  if (!anchorFrame) {
    anchorFrame = requestAnimationFrame(function () { anchorFrame = 0; captureAnchor(); });
  }
});

/* Images decoding, cards opening, the alerts bar appearing: all change sizes
   without a scroll event. Observed here, corrected before the frame is drawn. */
if (window.ResizeObserver) {
  var sizeWatch = new ResizeObserver(function () { settle(); });
  sizeWatch.observe(document.getElementById('log'));
  sizeWatch.observe(document.getElementById('logscroll'));
}

function showPill(text) {
  var pill = document.getElementById('newpill');
  pill.textContent = text;
  pill.className = 'on';
}

function hidePill() {
  document.getElementById('newpill').className = '';
}

document.getElementById('newpill').addEventListener('click', function () {
  stickBottom = true;
  hidePill();
  toBottom();
});

function toBottom() {
  var box = document.getElementById('logscroll');
  box.scrollTop = box.scrollHeight;
}

function keepBottom(work) {
  work();
  settle();
}

function stateOf(path) {
  if (!cardState[path]) { cardState[path] = { open: false, edit: false, note: '', warn: false }; }
  return cardState[path];
}

function baseName(path) {
  var parts = String(path).split('/');
  return parts[parts.length - 1] || path;
}

function extOf(path) {
  var name = baseName(path);
  var dot = name.lastIndexOf('.');
  return dot > 0 ? name.slice(dot + 1).toLowerCase() : '';
}

function niceSize(n) {
  if (!n && n !== 0) { return ''; }
  if (n < 1024) { return n + 'B'; }
  if (n < 1048576) { return Math.round(n / 1024) + 'KB'; }
  return (Math.round(n / 104857.6) / 10) + 'MB';
}

function chipFor(path) {
  var chip = el('span', 'chip' + (stateOf(path).open ? ' on' : ''));
  chip.appendChild(el('span', null, baseName(path)));
  chip.appendChild(el('span', 'cx', extOf(path)));
  chip.addEventListener('click', function (e) {
    e.preventDefault();
    e.stopPropagation();
    // עמוד נפתח בדפדפן בלחיצה אחת. כרטיס עם קוד־מקור אינו מה שרוצים
    // לראות כששולחים קישור לעמוד.
    if (isPage(path)) { send('reveal', { path: path }); return; }
    toggleCard(path);
  });
  if (pendingCards.indexOf(path) < 0) { pendingCards.push(path); }
  return chip;
}

function toggleCard(path) {
  var st = stateOf(path);
  st.open = !st.open;
  st.shutByHand = !st.open;
  if (st.open && !assets[path]) { send('asset', { path: path }); }
  if (!st.open) { st.edit = false; if (editingPath === path) { editingPath = null; } }
  keepBottom(function () { renderCard(path); });
}

function setAsset(payload) {
  if (!payload || !payload.path) { return; }
  var waiting = mdImgWait[payload.path];
  if (waiting) {
    delete mdImgWait[payload.path];
    assets[payload.path] = payload;
    waiting.forEach(function (img) {
      if (payload.src) { img.src = payload.src; } else { img.alt += ' — ' + (payload.error || ''); }
    });
    return;
  }
  assets[payload.path] = payload;
  var st = stateOf(payload.path);
  if (payload.note) { st.note = payload.note; st.warn = !!payload.warn; }
  // A failed save used to close the editor and lose the draft. ⌘S stays.
  if (payload.note && !payload.warn && !payload.stay) { st.edit = false; editingPath = null; }
  if (!st.open && !st.shutByHand && !workNodes[payload.path] && !outNodes[payload.path] && !payload.error && payload.kind !== 'image'
      && payload.size && payload.size < SELF_OPEN) {
    st.open = true;
  }
  keepBottom(function () { renderCard(payload.path); });
  if (clipped.indexOf(payload.path) >= 0) { drawClips(); }
}

function cardButton(label, fn) {
  var b = el('span', 'cardbtn', label);
  b.addEventListener('click', function (e) { e.stopPropagation(); fn(); });
  return b;
}

/* One file can be on screen in three places at once — in the conversation,
   in the outputs list, and in the conversation's own outputs strip. They
   share one open/closed state, and each is drawn. */
var outNodes = {};
var askNodes = {};
function renderCard(path) {
  var seen = [];
  [cardNodes[path], workNodes[path], outNodes[path], askNodes[path]].forEach(function (card) {
    if (card && seen.indexOf(card) < 0) { seen.push(card); renderCardInto(path, card); }
  });
}

function renderCardInto(path, card) {
  var st = stateOf(path);
  var asset = assets[path];
  card.className = 'card' + (card.__extra || '') + (st.open ? '' : ' shut');

  var bar = card.firstChild;
  bar.textContent = '';
  bar.appendChild(el('span', 'cardkind', st.open ? '▾' : '▸'));
  bar.appendChild(el('span', 'cardname', baseName(path)));
  var meta = card.__meta;
  if (meta) {
    /* outputs list / session outputs: where it lives and when it was made */
    bar.appendChild(el('span', 'cardkind workkind', meta.kind || extOf(path)));
    if (meta.folder) { bar.appendChild(el('span', 'cardkind workfolder', meta.folder)); }
    else if (meta.project) { bar.appendChild(el('span', 'cardkind workproj', meta.project)); }
    bar.appendChild(el('span', 'cardkind', (meta.when || meta.age || '') + (meta.size ? ' · ' + meta.size : '')));
  } else {
    bar.appendChild(el('span', 'cardkind',
      extOf(path) + (asset && asset.size ? ' · ' + niceSize(asset.size) : '')));
  }
  if (st.note) {
    var note = el('span', 'cardnote' + (st.warn ? ' warn' : ''), st.note);
    bar.appendChild(note);
  }

  var btns = el('span', 'cardbtns');
  if (st.open && asset && !asset.error) {
    if (asset.kind !== 'image' && asset.kind !== 'pdf') {
      if (st.edit) {
        btns.appendChild(cardButton('\(Lang.t("שמירה", "Save"))', function () {
          var text = cardText(path, card);
          if (text !== null) { st.dirty = false; send('saveAsset', { path: path, text: text }); }
        }));
        btns.appendChild(cardButton('\(Lang.t("ביטול", "Cancel"))', function () {
          // a draft is not thrown away on one click
          if (st.dirty && !st.cancelArmed) {
            st.cancelArmed = true;
            st.note = '\(Lang.t("יש שינויים שלא נשמרו — לחיצה נוספת מבטלת אותם", "Unsaved changes — click again to discard them"))';
            st.warn = true;
            setTimeout(function () { st.cancelArmed = false; }, 5000);
            renderCard(path);
            return;
          }
          st.edit = false; st.dirty = false; st.cancelArmed = false; st.note = '';
          if (editingPath === path) { editingPath = null; }
          renderCard(path);
        }));
      } else {
        btns.appendChild(cardButton('\(Lang.t("עריכה", "Edit"))', function () {
          st.edit = true;
          st.note = '';
          editingPath = path;
          renderCard(path);
        }));
      }
    }
    // ⇒ הלוח הצדדי מרנדר טקסט; ‏PDF אינו טקסט, ולחיצה שם הייתה מציגה ג׳יבריש
    if (asset.kind !== 'pdf') {
      btns.appendChild(cardButton(meta ? '\(Lang.t("קריאה במסך מלא", "Full-window reader"))' : '\(Lang.t("בלוח", "on the board"))',
        function () { send('openDoc', { path: path, reader: !!meta }); }));
    }
    btns.appendChild(cardButton(isPage(path) ? '\(Lang.t("בדפדפן", "In browser"))' : '\(Lang.t("פתיחה בחוץ", "Open outside"))', function () {
      send('reveal', { path: path });
    }));
  }
  btns.appendChild(cardButton(st.open ? '\(Lang.t("סגירה", "Close"))' : '\(Lang.t("פתיחה", "Open"))', function () { toggleCard(path); }));
  bar.appendChild(btns);

  var body = card.lastChild;
  body.textContent = '';
  if (!st.open) { return; }

  if (!asset) {
    var wait = el('div', 'cardmiss');
    wait.appendChild(spinner(15));
    wait.appendChild(el('span', null, '\(Lang.t(" נטען…", " loading…"))'));
    body.appendChild(wait);
    return;
  }
  if (asset.error) { body.appendChild(el('div', 'cardmiss', asset.error)); return; }

  /* ‏**עמודי ה-PDF מגיעים כתמונות.** מנוע־הדפדפן אינו מציג PDF בדף שנטען
     כמחרוזת, ולכן הרינדור נעשה בצד סוויפט. ר׳ ההסבר ב-`Documents.asset`. */
  if (asset.kind === 'pdf') {
    var shots = asset.shots || [];
    if (!shots.length) {
      body.appendChild(el('div', 'cardmiss', '\(Lang.t("לא הצלחתי לצייר את העמודים", "Could not render the pages"))'));
      return;
    }
    shots.forEach(function (src) {
      var page = document.createElement('img');
      page.className = 'cardimg';
      page.src = src;
      page.addEventListener('click', function () {
        page.className = page.className === 'cardimg' ? 'cardimg full' : 'cardimg';
      });
      body.appendChild(page);
    });
    if (asset.pages > shots.length) {
      body.appendChild(el('div', 'cardmiss',
        '\(Lang.t("מוצגים ", "showing "))' + shots.length + '\(Lang.t(" מתוך ", " of "))' + asset.pages + '\(Lang.t(" עמודים — השאר בפתיחה בחוץ", " pages — the rest open outside"))'));
    }
    return;
  }

  if (asset.kind === 'image') {
    var img = document.createElement('img');
    img.className = 'cardimg';
    img.src = asset.src;
    img.addEventListener('click', function () {
      img.className = img.className === 'cardimg' ? 'cardimg full' : 'cardimg';
    });
    body.appendChild(img);
    return;
  }

  if (!st.edit) { dropCardEditor(path); }
  if (st.edit && window.PeachEditor) {
    var ce = cardEditor(path, asset.text || '');
    body.appendChild(ce.host);   // the same editor moves back in on a re-render: draft, caret, undo kept
    ce.ed.focus();
    return;
  }
  if (st.edit) {
    var box = document.createElement('textarea');
    box.className = 'cardedit';
    box.spellcheck = false;
    box.value = asset.text || '';
    body.appendChild(box);
    box.focus();
    return;
  }

  if (asset.kind === 'md') {
    var view = el('div', 'md');
    cardsEnabled = false;
    view.appendChild(md(asset.text || '', []));
    cardsEnabled = true;
    body.appendChild(view);
  } else {
    body.appendChild(preLinked('cardraw', asset.text || ''));
  }
}

var IMAGE_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'heic', 'bmp'];

function isImage(path) { return IMAGE_EXT.indexOf(extOf(path)) >= 0; }

/* ‏PDF נפתח מאליו כמו תמונה — הוא נראה, לא נקרא כטקסט */
function isSeen(path) { return isImage(path) || extOf(path) === 'pdf'; }

function isPage(path) {
  var e = extOf(path);
  return e === 'html' || e === 'htm' || e === 'svg' || e === 'pdf';
}

/* מסמך קצר ששמו הוזכר לאחרונה — נפתח מעצמו. מסמך גדול נשאר סגור:
   אלף שורות שנפרשות באמצע השיחה מסתירות את השיחה עצמה. */
var SELF_OPEN = 14000;

/* תמונות נפתחות מעצמן, כמו בצ׳אט המקוון — אבל רק האחרונות. שיחה עם
   עשרים צילומים הייתה מטמיעה עשרות מגהבייטים בדף בבת־אחת. */
function autoOpenImages() {
  var all = Object.keys(cardNodes);
  all.filter(isSeen).slice(-4).forEach(function (path) {
    if (!stateOf(path).open) { toggleCard(path); }
  });
  // מסמכי־טקסט: מבקשים את התוכן כדי לדעת את גודלו, ומחליטים בהגעה
  all.filter(function (p) { return !isSeen(p); }).slice(-2).forEach(function (path) {
    if (!assets[path]) { send('asset', { path: path }); }
  });
}

/* עריכה ושמירה מהמקלדת — בלי להגיע לכפתור. הכרטיס הפתוח האחרון קודם
   ללוח הצדדי, כי הוא זה שנמצא מול העיניים. */
function editTopCard() {
  var open = Object.keys(cardNodes).filter(function (p) {
    return stateOf(p).open && !isImage(p) && assets[p] && !assets[p].error;
  });
  if (!open.length) { return false; }
  var path = open[open.length - 1];
  stateOf(path).edit = true;
  stateOf(path).note = '';
  editingPath = path;
  renderCard(path);
  return true;
}

/* File cards edit in the same CodeMirror editor as the document pane. One
   editor per path, kept across re-renders and dropped when editing ends. */
var cardEds = {};

function cardEditor(path, text) {
  if (cardEds[path]) { return cardEds[path]; }
  var host = el('div', 'cardcm');
  var ed = window.PeachEditor.create(host, text, function () { markCardDirty(path); },
                                     { markdown: extOf(path) === 'md' });
  cardEds[path] = { host: host, ed: ed };
  return cardEds[path];
}

function dropCardEditor(path) {
  var c = cardEds[path];
  if (!c) { return; }
  c.ed.destroy();
  delete cardEds[path];
}

function markCardDirty(path) {
  var st = stateOf(path);
  if (st.dirty) { return; }
  st.dirty = true;
  st.note = UNSAVED; st.warn = true;
  [cardNodes[path], workNodes[path], outNodes[path], askNodes[path]].forEach(function (card) {
    if (!card) { return; }
    var bar = card.firstChild, n = bar.querySelector('.cardnote');
    if (!n) { n = el('span', 'cardnote'); bar.insertBefore(n, bar.querySelector('.cardbtns')); }
    n.textContent = UNSAVED; n.className = 'cardnote warn';
  });
}

function cardText(path, card) {
  if (cardEds[path]) { return cardEds[path].ed.value; }
  var box = card && card.lastChild.querySelector('.cardedit');
  return box ? box.value : null;
}

function saveAnything() {
  // the editor with the caret wins when a card and the document both edit
  if (cm && cm.view.hasFocus) { docDirty = false; send('saveDoc', { text: edValue(), stay: true }); return true; }
  if (editingPath && cardEds[editingPath]) {
    stateOf(editingPath).dirty = false;
    send('saveAsset', { path: editingPath, text: cardEds[editingPath].ed.value, stay: true });
    return true;
  }
  var editNode = editingPath && [cardNodes[editingPath], workNodes[editingPath], outNodes[editingPath]]
    .filter(function (n) { return n && n.offsetParent !== null; })[0];
  if (editNode) {
    var box = editNode.lastChild.querySelector('.cardedit');
    if (box) { send('saveAsset', { path: editingPath, text: box.value }); return true; }
  }
  if (edOpen()) { docDirty = false; send('saveDoc', { text: edValue(), stay: true }); return true; }
  return false;
}

function attachCards(host) {
  if (!cardsEnabled) { pendingCards = []; return; }
  if (!pendingCards.length) { return; }
  pendingCards.forEach(function (path) {
    var card = el('div', 'card shut');
    card.appendChild(el('div', 'cardbar'));
    card.appendChild(el('div', 'cardbody'));
    card.firstChild.addEventListener('click', function () { toggleCard(path); });
    cardNodes[path] = card;
    host.appendChild(card);
    renderCard(path);
  });
  pendingCards = [];
}

/* טקסט מרקדאון → אלמנטים. מנתח־שורות ולא ביטויים רגולריים: תבנית אחת
   שגויה על טקסט עברי מוחקת פסקה שלמה בשקט, ומנתח־שורות תמיד מחזיר משהו. */
function md(text, paths) {
  /* קריאה מקוננת (תוכן של כרטיס) דורסת את המצב של הקריאה החיצונית —
     בלי השמירה הזאת, בלוקים שאחרי הכרטיס הראשון היו מאבדים את הנתיבים. */
  var keepPaths = livePaths;
  var keepPending = pendingCards;
  pendingCards = [];
  livePaths = paths || [];

  var root = document.createDocumentFragment();
  var lines = String(text).split(NL);
  var i = 0;
  var para = [];

  function push(node) {
    root.appendChild(node);
    attachCards(root);
  }

  function flushPara() {
    if (!para.length) { return; }
    var p = el('p');
    p.appendChild(inline(para.join(NL)));
    push(p);
    para = [];
  }

  while (i < lines.length) {
    var line = lines[i];
    var t = line.trim();

    if (t === '') { flushPara(); i++; continue; }

    if (t.slice(0, 3) === '```') {
      flushPara();
      var lang = t.slice(3).trim().toLowerCase();
      var buf = [];
      i++;
      while (i < lines.length && lines[i].trim().slice(0, 3) !== '```') { buf.push(lines[i]); i++; }
      i++;
      push(lang ? highlight(lang, buf.join(NL)) : preLinked(null, buf.join(NL)));
      continue;
    }

    if (t.length >= 3 && (t.split('-').join('') === '' || t.split('=').join('') === '')) {
      flushPara();
      push(el('hr'));
      i++;
      continue;
    }

    var h = heading(t);
    if (h) { flushPara(); push(h); i++; continue; }

    if (t.charAt(0) === '>') {
      flushPara();
      var quote = [];
      while (i < lines.length && lines[i].trim().charAt(0) === '>') {
        var q = lines[i].trim().slice(1);
        quote.push(q.charAt(0) === ' ' ? q.slice(1) : q);
        i++;
      }
      var bq = el('blockquote');
      bq.appendChild(md(quote.join(NL), livePaths));
      push(bq);
      continue;
    }

    var cells = tableRow(line);
    if (cells) {
      flushPara();
      var rows = [];
      while (i < lines.length) {
        var r = tableRow(lines[i]);
        if (!r) { break; }
        rows.push(r);
        i++;
      }
      var table = el('table');
      var aligns = [];
      rows.forEach(function (row, ri) {
        if (ri === 1 && isDivider(row)) {
          aligns = row.map(function (c) {
            var l = c.charAt(0) === ':', r = c.charAt(c.length - 1) === ':';
            return l && r ? 'center' : r ? 'right' : l ? 'left' : '';
          });
          return;
        }
        var tr = el('tr');
        row.forEach(function (c, ci) {
          var cell = el(ri === 0 ? 'th' : 'td');
          if (aligns[ci]) { cell.style.textAlign = aligns[ci]; }
          cell.appendChild(inline(c));
          tr.appendChild(cell);
        });
        table.appendChild(tr);
      });
      push(table);
      continue;
    }

    var b = bulletOf(line);
    if (b) {
      flushPara();
      /* Indented items nest inside the item above them. Until 30.10 they
         were flat siblings with a margin, so an English sub-item under a
         Hebrew item jumped to the far side of the page. */
      var stack = [];
      var list = null;
      while (i < lines.length) {
        var item = bulletOf(lines[i]);
        if (!item) { break; }
        while (stack.length > 1 && item.indent < stack[stack.length - 1].indent) { stack.pop(); }
        var top = stack[stack.length - 1];
        if (top && !top.li) { break; }
        if (top && stack.length === 1 && item.indent <= top.indent && item.ordered !== top.ordered) { break; }
        if (!top || item.indent > top.indent) {
          var nl = el(item.ordered ? 'ol' : 'ul');
          if (item.ordered && item.num !== 1) { nl.start = item.num; }
          if (top) { top.li.appendChild(nl); } else { list = nl; }
          top = { indent: item.indent, ordered: item.ordered, list: nl, li: null };
          stack.push(top);
        }
        var li = el('li');
        top.list.appendChild(li);
        top.li = li;
        var body = item.text;
        if (body.slice(0, 4) === '[ ] ') {
          li.appendChild(el('span', 'task', '☐ '));
          body = body.slice(4);
        } else if (body.slice(0, 4).toLowerCase() === '[x] ') {
          li.appendChild(el('span', 'done', '☑ '));
          body = body.slice(4);
        }
        var words = el('span', 'lit');
        words.dir = 'auto';
        words.appendChild(inline(body));
        li.appendChild(words);
        i++;
      }
      push(list);
      continue;
    }

    para.push(line);
    i++;
  }
  flushPara();
  blockDirs(root);
  livePaths = keepPaths;
  pendingCards = keepPending;
  return root;
}

/* Every block runs in its own direction. The page is right-to-left, and an
   English document rendered into it came out with its full stops in front
   and its list numbers on the wrong side (measured 28.10 on plan cards, the
   reader and the chat log). Blocks take dir=auto; lists and tables take an
   explicit dir from their first letter, because dir=auto on a container
   skips children that carry their own dir — a Hebrew list came out LTR. */
/* The first letter with a direction decides: Hebrew, Arabic and the RLM
   mark are right-to-left; Latin and the LRM mark are left-to-right. */
function firstStrongDir(text) {
  for (var q = 0; q < text.length; q++) {
    var c = text.charCodeAt(q);
    if (c === 0x200F || (c >= 0x590 && c <= 0x8FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF && c !== 0xFEFF)) { return 'rtl'; }
    if (c === 0x200E || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 0xC0 && c <= 0x24F) || (c >= 0x370 && c <= 0x52F)) { return 'ltr'; }
  }
  return '';
}

function blockDirs(root) {
  /* Computed here rather than left to dir=auto: auto skips isolated runs,
     so a paragraph that opens with a path (now an isolate) took the
     direction of the Hebrew after it. */
  root.querySelectorAll('p, h1, h2, h3, h4, h5, h6, th, td')
    .forEach(function (n) {
      // no letter at all (a cell of numbers): follow the container instead of guessing LTR
      var d = firstStrongDir(n.textContent);
      if (d) { n.dir = d; }
    });
  root.querySelectorAll('ol, ul, table, blockquote').forEach(function (n) {
    n.dir = firstStrongDir(n.textContent) || 'ltr';
  });
  /* An item stays on its list's side, bullet and all; its own words still
     order themselves from their first letter. An
     English sub-item under a Hebrew item used to jump to the far margin.
     The words sit in span.lit, dir=auto, so they order from their own first
     letter while the bullet stays put. */
  root.querySelectorAll('li').forEach(function (n) { n.dir = n.parentNode.dir || 'auto'; });
}

/* A small highlighter for fenced code with a language: comments, strings,
   numbers and keywords. A scanner rather than regular expressions, because
   this page lives in a Swift string where a backslash is Swift's. */
var HL_KEYWORDS = {};
('let var const function return if else for while do switch case break continue class struct enum ' +
 'func import from export default new try catch finally throw async await def elif in not and or is ' +
 'None True False true false null nil undefined self this guard static public private extension ' +
 'protocol where echo then fi esac done local type interface package go fn pub mut use impl match')
  .split(' ').forEach(function (k) { HL_KEYWORDS[k] = true; });
var HL_HASH = ['py', 'python', 'sh', 'bash', 'zsh', 'shell', 'yaml', 'yml', 'rb', 'ruby', 'toml', 'r'];
var BS = String.fromCharCode(92);

function highlight(lang, text) {
  var pre = el('pre', 'hl');
  pre.dataset.lang = lang;
  var hash = HL_HASH.indexOf(lang) >= 0;
  var n = text.length, i = 0, buf = '';
  function isWord(ch) { return /[A-Za-z0-9_$]/.test(ch); }
  function flush() { if (buf) { pre.appendChild(document.createTextNode(buf)); buf = ''; } }
  function tok(cls, s) { flush(); pre.appendChild(el('span', 't-' + cls, s)); }
  while (i < n) {
    var c = text.charAt(i);
    if ((c === '/' && text.charAt(i + 1) === '/') || (hash && c === '#')) {
      var e = text.indexOf(NL, i); if (e < 0) { e = n; }
      tok('c', text.slice(i, e)); i = e; continue;
    }
    if (c === '/' && text.charAt(i + 1) === '*') {
      var e2 = text.indexOf('*' + '/', i + 2); e2 = e2 < 0 ? n : e2 + 2;
      tok('c', text.slice(i, e2)); i = e2; continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      var j = i + 1;
      while (j < n && text.charAt(j) !== c && text.charAt(j) !== NL) { if (text.charAt(j) === BS) { j++; } j++; }
      j = Math.min(j + 1, n);
      tok('s', text.slice(i, j)); i = j; continue;
    }
    if (/[0-9]/.test(c) && !isWord(text.charAt(i - 1))) {
      var k = i; while (k < n && (isWord(text.charAt(k)) || text.charAt(k) === '.')) { k++; }
      tok('n', text.slice(i, k)); i = k; continue;
    }
    if (/[A-Za-z_$]/.test(c)) {
      var k2 = i; while (k2 < n && isWord(text.charAt(k2))) { k2++; }
      var w = text.slice(i, k2);
      if (HL_KEYWORDS[w]) { tok('k', w); } else { buf += w; }
      i = k2; continue;
    }
    buf += c; i++;
  }
  flush();
  return pre;
}

/* ================= שאלה שנשאלה במסוף ================= */

/* ⛔ שאלה חוסמת את המסוף עד שעונים לה. עד שהכרטיס הזה נבנה היא הייתה
   קיימת ביומן ובלתי־נראית בפיץ׳ — המסוף נראה "ממתין לך" ותו לא. */
var freeButton = null;
function freeDone(ok, why) {
  if (!freeButton) { return; }
  freeButton.firstChild.textContent = ok ? '\(Lang.t("נשלח", "sent"))'
    : ('\(Lang.t("לא נשלח", "Not sent"))' + (why ? ' — ' + why : '\(Lang.t(" — פתח את המסוף", " — open the terminal"))'));
  freeButton = null;
}

function askCard(a, where) {
  var box = el('div', 'askcard');

  var head = el('div', 'askcardhead');
  head.appendChild(el('span', 'askkind', a.kind === 'plan' ? '\(Lang.t("מבקש אישור", "wants approval"))' : '\(Lang.t("שואל אותך", "asking you"))'));
  if (a.since) { head.appendChild(el('span', 'asksince', a.since)); }
  if (where && a.title) {
    var w = el('span', 'askwhere');
    // ⛔ מספר־עמדה ושם נדבקו זה לזה: הרווח שבמחרוזת נבלע בסידור הדו־כיווני.
    //    מרווח אמיתי בא מהפריסה, לא מתו־רווח בתוך טקסט מעורב.
    if (a.slot) { w.appendChild(el('span', 'askslot', a.slot)); }
    w.appendChild(el('span', 'askname', a.title));
    head.appendChild(w);
  }
  box.appendChild(head);

  /* ⛔ The question alone is a riddle: the session explains it in the
     message right above, and that message is not in the transcript while
     the question is open (measured 3.10). The card carries it. */
  if (a.context) {
    var cx = el('div', 'md askcontext');
    cardsEnabled = false;
    cx.appendChild(md(a.context, []));
    cardsEnabled = true;
    box.appendChild(cx);
  }
  /* Files the explanation names open right here — an image shows at once.
     Closing one is remembered, like everywhere else. */
  (a.paths || []).forEach(function (path) {
    var card = askNodes[path];
    if (!card) {
      card = el('div', 'card shut');
      card.__extra = ' askfile';
      card.appendChild(el('div', 'cardbar'));
      card.appendChild(el('div', 'cardbody'));
      card.firstChild.addEventListener('click', function (e) { e.stopPropagation(); toggleCard(path); });
      askNodes[path] = card;
    }
    var st = stateOf(path);
    if (!st.shutByHand && !st.open) { st.open = true; }
    if (st.open && !assets[path]) { send('asset', { path: path }); }
    box.appendChild(card);
    renderCard(path);
  });

  if (a.plan) {
    var pv = el('div', 'md askplan');
    /* Each block's direction is set inside md() (blockDirs). */
    cardsEnabled = false;
    pv.appendChild(md(a.plan, []));
    cardsEnabled = true;
    box.appendChild(pv);
  }

  /* ⛔ שאלת־מסוף נשאלת **אחת בכל פעם**. אם יש כמה, רק הראשונה על המסך
        של המסוף — ולכן רק היא נענית מכאן. השאר מוצגות כדי לדעת מה בא,
        ולא כלחצנים שישלחו ספרה אל הבורר הלא־נכון. */
  (a.parts || []).forEach(function (part, pi) {
    var later = pi > 0;
    var qEl = el('div', 'askq' + (later ? ' later' : ''), part.question);
    qEl.dir = 'auto';
    box.appendChild(qEl);
    if (later) {
      box.appendChild(el('div', 'askmulti', '\(Lang.t("תישאל אחרי שתענה על הקודמת", "Will be asked after you answer the previous one"))'));
      return;
    }
    if (part.multi) {
      box.appendChild(el('div', 'askmulti',
        '\(Lang.t("במסוף אפשר לסמן כמה — לחיצה כאן בוחרת אחת ושולחת", "The terminal allows several — clicking here picks one and sends"))'));
    }
    var opts = el('div', 'askopts');
    (part.choices || []).forEach(function (c) {
      var b = document.createElement('button');
      b.className = 'opt';
      var lab = el('span', 'optlabel', c.label);
      lab.dir = 'auto';
      b.appendChild(lab);
      if (c.detail) { var det = el('span', 'optdetail', c.detail); det.dir = 'auto'; b.appendChild(det); }
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        send('answerAsk', { tty: a.tty, pick: c.n });
        b.className = 'opt sent';
      });
      opts.appendChild(b);
    });
    box.appendChild(opts);

    /* ⛔ תשובה חופשית **אינה** נשלחת מכאן, ולא בגלל עצלנות.
       נמדד חי מול הבורר: בחירה ב-"Type something" סוגרת את השאלה מיד עם
       ‏`__other__` ובלי טקסט, כי המקש שמנווט אל האפשרות הוא גם זה שמאשר
       אותה. הטקסט שנשלח אחריו נוחת בשורת־ההודעה, לא בשאלה.
       ⇒ לתשובה חופשית פותחים את המסוף עצמו. כפתור, לא תיבה שמשקרת. */
    if (!a.tty) { return; }
    var free = el('div', 'askfree');
    /* A background session has no window to type into: one button opens one,
       and from there the answer is a click like anywhere else. */
    if (a.windowless) {
      opts.querySelectorAll('button').forEach(function (b) { b.disabled = true; b.className = 'opt off'; });
      var openIt = document.createElement('button');
      openIt.className = 'opt';
      openIt.appendChild(el('span', 'optlabel', '\(Lang.t("השיחה רצה ברקע — לפתוח לה חלון כדי לענות", "Running in the background — open a window to answer"))'));
      openIt.addEventListener('click', function (e) { e.stopPropagation(); send('raiseTty', { tty: a.tty }); });
      free.appendChild(openIt);
      box.appendChild(free);
      return;
    }
    /* A free answer typed here goes into the console's own free-text row —
       arrow down, type, Enter, as a person would (measured 3.10). Only when
       the picker is on a readable screen and has that row. */
    if (a.freeRow > 0 && !part.multi) {
      var box2 = document.createElement('textarea');
      box2.className = 'askown';
      box2.placeholder = '\(Lang.t("או לכתוב תשובה במילים שלך…", "Or write your own answer…"))';
      box2.rows = 2;
      box2.addEventListener('click', function (e) { e.stopPropagation(); });
      box2.addEventListener('keydown', function (e) {
        e.stopPropagation();
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); go.click(); }
      });
      var go = document.createElement('button');
      go.className = 'opt';
      go.appendChild(el('span', 'optlabel', '\(Lang.t("שליחת התשובה", "Send the answer"))'));
      go.addEventListener('click', function (e) {
        e.stopPropagation();
        var t = box2.value.trim();
        if (!t) { box2.focus(); return; }
        go.className = 'opt sent';
        go.firstChild.textContent = '\(Lang.t("שולח…", "sending…"))';
        freeButton = go;
        send('answerFree', { tty: a.tty, text: t });
      });
      free.appendChild(box2);
      free.appendChild(go);
      box.appendChild(free);
      free = el('div', 'askfree');
    }
    var jump = document.createElement('button');
    jump.className = 'opt other';
    jump.appendChild(el('span', 'optlabel', '\(Lang.t("או לפתוח את המסוף", "Or open the terminal"))'));
    jump.addEventListener('click', function (e) {
      e.stopPropagation();
      send('raiseTty', { tty: a.tty });
    });
    free.appendChild(jump);
    box.appendChild(free);
  });
  return box;
}

/* ================= מדף ================= */

var onlyPath = '';
var lastRack = { units: [] };

/* While a name is being typed on the rack, the 1.5 s repaint would rebuild
   the row and throw the typing away. The rack waits until it is done. */
var rackEditing = false;

function paintRack(data) {
  lastRack = data;
  if (rackEditing) { return; }
  var all = data.units || [];
  /* ⛔ **סינון־פרויקט לעולם אינו מסתיר מסוף ששואל אותך.** נמדד: המונה
     למעלה נספר מ-`all` ואמר "1 שואלים אותך", בזמן שהשורה עצמה סוננה
     החוצה ולא הייתה בשום מקום במסך. ⇒ מספר שמצביע על שורה שאיננה הוא
     גרוע יותר מאין־מספר: הוא אומר שיש מה לענות ולא נותן על מה. */
  var units = onlyPath
    ? all.filter(function (u) { return u.path === onlyPath || (u.state === 'ask' && !u.muted); })
    : all;

  var sift = document.getElementById('sift');
  if (onlyPath) {
    sift.className = 'on';
    sift.textContent = '';
    sift.appendChild(el('span', null, ''));
    sift.firstChild.remove();
    sift.appendChild(document.createTextNode('\(Lang.t("מוצג רק ", "showing only "))'));
    sift.appendChild(el('b', null, onlyPath));
    var inPath = all.filter(function (u) { return u.path === onlyPath; }).length;
    var pulled = units.length - inPath;
    sift.appendChild(document.createTextNode(' · ' + inPath + '\(Lang.t(" מתוך ", " of "))' + all.length));
    if (pulled > 0) {
      sift.appendChild(el('b', 'pulled', ' + ' + pulled + '\(Lang.t(" ששואלים אותך", " asking you"))'));
    }
    var off = el('span', null, '\(Lang.t("להציג הכול", "Show everything"))');
    off.addEventListener('click', function () { onlyPath = ''; paintRack(lastRack); });
    sift.appendChild(off);
  } else {
    sift.className = '';
    sift.textContent = '';
  }
  var readout = document.getElementById('readout');
  readout.textContent = '';
  var running = all.filter(function (u) { return u.state === 'run'; }).length;
  var waiting = all.filter(function (u) { return u.state === 'wait'; }).length;
  readout.appendChild(stat('', all.length, '\(Lang.t("מסופים", "terminals"))'));
  var asking = all.filter(function (u) { return u.state === 'ask' && !u.muted; }).length;
  readout.appendChild(stat('run', running, '\(Lang.t("עובדים", "working"))'));
  readout.appendChild(stat('wait', waiting, '\(Lang.t("ממתינים לך", "waiting for you"))'));
  if (asking) { readout.appendChild(stat('ask', asking, '\(Lang.t("שואלים אותך", "asking you"))')); }
  document.getElementById('clock').textContent = data.clock || '';
  setPace(running);

  // ⇒ הכפתור קיים רק כשיש את מי להעיר, ואומר כמה — לא "להעיר" סתם
  var wake = document.getElementById('wakeall');
  wake.className = 'btn' + (waiting ? '' : ' off');
  wake.textContent = '\(Lang.t("להעיר ", "wake "))' + waiting;

  var host = document.getElementById('units');
  host.textContent = '';
  rackRows = [];
  rackSlots = [];
  if (!units.length) {
    var none = el('div', null, '\(Lang.t("אין מסופים פתוחים.", "No open terminals."))');
    none.id = 'empty';
    host.appendChild(none);
    return;
  }

  units.forEach(function (u) {
    var row = el('div', 'unit ' + u.state + (u.muted ? ' muted' : ''));
    row.appendChild(el('div', 'slot', u.slot));

    var lamp = el('div', 'lamp');
    lamp.appendChild(el('span', 'bulb'));
    lamp.appendChild(el('span', 'state', u.stateLabel));
    row.appendChild(lamp);

    /* The name, with a pencil to rename the conversation itself — written
       into its log like /rename, so the console and /resume see it too. */
    var head = el('div', 'head');
    var nameEl = el('span', 'nm', u.title);
    head.appendChild(nameEl);
    if (u.sid) {
      var pen = el('span', 'pen', '✎');
      pen.title = '\(Lang.t("שינוי שם לשיחה", "Rename the conversation"))';
      pen.addEventListener('click', function (e) {
        e.stopPropagation();
        rackEditing = true;
        nameEl.contentEditable = 'true';
        nameEl.className = 'nm editing';
        nameEl.focus();
        document.getSelection().selectAllChildren(nameEl);
        var done = false;
        function finish(save) {
          if (done) { return; }
          done = true;
          rackEditing = false;
          nameEl.contentEditable = 'false';
          nameEl.className = 'nm';
          var name = nameEl.textContent.trim();
          if (save && name && name !== u.title) { send('rename', { sid: u.sid, name: name, real: true }); }
          else { nameEl.textContent = u.title; }
        }
        nameEl.onkeydown = function (k) {
          k.stopPropagation();
          if (k.key === 'Enter') { k.preventDefault(); finish(true); }
          if (k.key === 'Escape') { k.preventDefault(); finish(false); }
        };
        nameEl.onclick = function (k) { k.stopPropagation(); };
        nameEl.onblur = function () { finish(true); };
      });
      head.appendChild(pen);
    }
    row.appendChild(head);

    var meta = el('div', 'meta');
    if (u.chain) { meta.appendChild(el('span', 'chain', u.chain)); meta.appendChild(el('span', 'sep', '·')); }
    if (u.model) { meta.appendChild(el('span', null, u.model)); }
    if (u.context) {
      meta.appendChild(el('span', 'sep', '·'));
      /* A conversation that fills up loses itself. "warn" (default 70%)
         lights the badge; "ask" (default 75%) is where Peach asks for the
         hand-off. Both lines come from the menu setting. */
      var lvl = u.ctxLevel || '';
      var ctx = el('div', 'pair' + (lvl === 'ask' ? ' heavy' : (lvl === 'warn' ? ' warm' : '')));
      ctx.appendChild(el('span', 'num', u.context));
      ctx.appendChild(el('span', 'l', lvl ? Math.round(u.full * 100) + '\(Lang.t("% הקשר", "% context"))' : '\(Lang.t("הקשר", "context"))'));
      if (lvl) { ctx.title = '\(Lang.t("חלון־ההקשר מתמלא — פיץ׳ יבקש מסירה בסף שנקבע בתפריט", "The context window is filling — Peach asks for a hand-off at the menu threshold"))'; }
      meta.appendChild(ctx);
    }
    // ⇒ הצריכה של היום, על השורה עצמה. מספר שיושב רק במסך נפרד אינו נקרא.
    //   שיעור ולא סכום: המשתמש במנוי, ומחיר־רשימה אינו מה שהוא משלם.
    if (u.share > 0.005) {
      meta.appendChild(el('span', 'sep', '·'));
      var sp = el('div', 'pair');
      sp.appendChild(el('span', 'num money', Math.round(u.share * 100) + '%'));
      sp.appendChild(el('span', 'l', '\(Lang.t("מהיום", "of today"))'));
      meta.appendChild(sp);
    }
    meta.appendChild(el('span', 'sep', '·'));
    meta.appendChild(el('span', 'age', u.age));
    row.appendChild(meta);

    var sub = el('div', 'sub');
    if (u.agents) { sub.appendChild(el('span', 'agents', u.agents + '\(Lang.t(" סוכנים", " agents"))')); }
    // ⛔ "ממתין לך" אינו אומר על מה. כשיש שאלה — היא שורת־המשנה.
    /* ⇒ שאלה שנראית על המסך אך טרם נכתבה ליומן מגיעה בלי אפשרויות.
       אין לה מה למלא בשורת־האפשרויות, אבל **יש לה טקסט**, וזה כל מה
       שצריך כדי לדעת שיש לאן לקפוץ. */
    var asked = u.ask && u.ask.parts && u.ask.parts[0];
    var unwritten = u.ask && u.ask.unwritten;
    var line = asked ? asked.question : (unwritten ? u.ask.question : u.say);
    sub.appendChild(el('span', 'say' + (asked || unwritten ? ' asking' : ''), line));
    if (unwritten) {
      var raw = el('span', 'raw', '\(Lang.t("טרם ביומן — לחיצה פותחת את החלון", "Not in the log yet — click to open the window"))');
      raw.addEventListener('click', function (e) {
        e.stopPropagation();
        send('raise', { tty: u.tty });
      });
      sub.appendChild(raw);
    }
    /* ⇒ נמדד על 21 יום: 376 הודעות קצרות, וכמעט כולן שלוש המשפחות האלה.
       כל אחת מהן הייתה פתיחת שיחה, הקלדה, וחזרה למדף. */
    /* Reported 3.10: "continue" / "retry" were not needed. What was missing
       was a way to take a conversation down from the top. It comes back up
       by itself when anything new happens in it. */
    /* The hand-off is written: one click clears this terminal and continues
       from the file in a fresh conversation, same name with "· המשך". */
    if (u.relay === 'ready' || u.relay === 'go') {
      var rq = el('div', 'quick relay');
      var go = el('span', u.relay === 'go' ? 'relaywait' : 'relaygo',
                  u.relay === 'go' ? '\(Lang.t("ממתין לרגע שקט…", "Waiting for a quiet moment…"))'
                                   : '\(Lang.t("המשך בשיחה חדשה", "Continue in a new conversation"))');
      if (u.relay === 'ready') {
        go.addEventListener('click', function (e) {
          e.stopPropagation();
          go.className = 'relaywait';
          go.textContent = '\(Lang.t("ממתין לרגע שקט…", "Waiting for a quiet moment…"))';
          send('relayGo', { sid: u.sid });
        });
      }
      rq.appendChild(go);
      /* Agents still out: /clear leaves their results in the old log, so say
         that the hand-off is where they are picked up. */
      if (u.relayAgents > 0) {
        var an = el('span', 'relaywait', u.relayAgents + '\(Lang.t(" סוכנים עדיין רצים — את התוצאות שלהם ממשיכים מהמסירה", " agents still running — their results are picked up from the hand-off"))');
        rq.appendChild(an);
      } else if (u.relayShell) {
        rq.appendChild(el('span', 'relaywait', '\(Lang.t("משימות־רקע עדיין רצות — את התוצאות שלהן ממשיכים מהמסירה", "background tasks still running — their results are picked up from the hand-off"))'));
      }
      sub.appendChild(rq);
    }
    var quick = el('div', 'quick');
    var down = el('span', null, u.muted ? '\(Lang.t("להחזיר למעלה", "Back to the top"))' : '\(Lang.t("להוריד מהראש", "Take down"))');
    down.addEventListener('click', function (e) {
      e.stopPropagation();
      send('mute', u.muted ? { sid: u.sid } : { sid: u.sid, stamp: u.stamp });
    });
    quick.appendChild(down);
    sub.appendChild(quick);
    sub.appendChild(el('span', 'hint', '\(Lang.t("לחיצה פותחת את השיחה", "Click opens the conversation"))'));
    /* ⇒ **שיוך לפרויקט בלי ממשק חדש.** הנתיב כבר על השורה; לחיצה עליו
       מצמצמת את המדף לאותו פרויקט, ולחיצה שנייה מחזירה. */
    if (u.path) {
      var outside = onlyPath && u.path !== onlyPath;
      var path = el('span', 'path' + (u.path === onlyPath ? ' on' : '')
                             + (outside ? ' outside' : ''), u.path);
      path.title = outside ? '\(Lang.t("שואל אותך, מחוץ לסינון הנוכחי", "Asking you, outside the current filter"))'
                           : '\(Lang.t("לחיצה מצמצמת לפרויקט הזה", "Click to narrow to this project"))';
      path.addEventListener('click', function (e) {
        e.stopPropagation();
        onlyPath = (onlyPath === u.path) ? '' : u.path;
        paintRack(lastRack);
      });
      sub.appendChild(path);
    }
    row.appendChild(sub);

    row.addEventListener('click', function () { send('open', { sid: u.sid }); });
    host.appendChild(row);
    rackRows.push(row);
    // ‏"011" נקרא בעין כ-11, ולכן שתי הצורות נשמרות: המוצגת והמנוקה מאפסים
    rackSlots.push({ slot: u.slot, num: String(parseInt(u.slot, 10) || 0),
                     title: u.title, sid: u.sid });
  });
  if (rackPick >= rackRows.length) { rackPick = rackRows.length - 1; }
  markPick();
  showDial();
}

/* ================= שאלות שממתינות לך ================= */

/* חלון אל קובץ־השאלות היחיד, לא מאגר נוסף. מה שנכתב כאן נכתב לשם. */
var asksSig = '';

function paintAsks(asks, live) {
  live = live || [];
  var open = asks.filter(function (a) { return !a.answered; }).length;
  var head = document.getElementById('askscount');
  head.textContent = '';
  head.style.marginInlineStart = 'auto';
  head.style.display = 'flex';
  head.style.gap = '18px';
  if (live.length) { head.appendChild(stat('ask', live.length, '\(Lang.t("מהמסופים", "from terminals"))')); }
  head.appendChild(stat('wait', open, '\(Lang.t("פתוחות", "open"))'));
  head.appendChild(stat('run', asks.length - open, '\(Lang.t("נענו", "answered"))'));

  // ציור מחדש רק כשהתוכן השתנה — אחרת תיבת־תשובה שנכתבת בה נמחקת
  var sig = asks.map(function (a) { return a.id + (a.answered ? '1' : '0'); }).join(',')
          + '|' + live.map(function (a) { return a.id; }).join(',');
  if (sig === asksSig) { return; }
  asksSig = sig;

  var host = document.getElementById('askslist');
  host.textContent = '';

  // ⛔ שאלות המסופים למעלה: הן חוסמות עבודה שרצה ברגע זה, ואילו שאלות
  //    הקובץ ממתינות ממילא. סדר הפוך היה קובר את הדחוף מתחת לצבור.
  if (live.length) {
    host.appendChild(el('div', 'livehead',
      live.length === 1 ? '\(Lang.t("מסוף אחד שואל אותך עכשיו", "One terminal is asking you now"))' : live.length + '\(Lang.t(" מסופים שואלים אותך עכשיו", " terminals are asking you now"))'));
    live.forEach(function (a) { host.appendChild(askCard(a, true)); });
  }
  if (!asks.length && !live.length) {
    var none = el('div', null, '\(Lang.t("אין שאלות פתוחות.", "No open questions."))');
    none.id = 'empty';
    host.appendChild(none);
    return;
  }

  asks.forEach(function (a) {
    var box = el('div', 'ask' + (a.answered ? ' done' : ''));

    var head = el('div', 'askhead');
    head.appendChild(el('span', 'askdot', a.urgency));
    head.appendChild(el('span', 'askid', a.id));
    head.appendChild(el('span', 'asktitle', a.title));
    if (a.cost) { head.appendChild(el('span', 'askcost', a.cost)); }
    if (a.asker) { head.appendChild(el('span', 'askfrom', a.asker)); }
    head.addEventListener('click', function () {
      box.className = box.className.indexOf('open') >= 0
        ? 'ask' + (a.answered ? ' done' : '')
        : 'ask open' + (a.answered ? ' done' : '');
    });
    box.appendChild(head);

    var body = el('div', 'askbody');
    var text = el('div', 'md');
    cardsEnabled = false;
    text.appendChild(md(a.body, []));
    cardsEnabled = true;
    body.appendChild(text);

    if (a.answered) {
      body.appendChild(el('div', 'asksaid', a.answer));
    }

    var reply = el('div', 'askreply');
    var box2 = document.createElement('textarea');
    box2.placeholder = a.answered ? '\(Lang.t("לשנות את התשובה", "Change the answer"))' : '\(Lang.t("לענות כאן", "Answer here"))';
    box2.rows = 2;
    reply.appendChild(box2);
    var send2 = el('span', 'btn', '\(Lang.t("לשלוח", "Send"))');
    send2.addEventListener('click', function () {
      var value = box2.value.trim();
      if (!value) { return; }
      box2.value = '';
      asksSig = '';
      send('answer', { id: a.id, text: value });
    });
    box2.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); send2.click(); }
    });
    reply.appendChild(send2);
    body.appendChild(reply);

    box.appendChild(body);
    host.appendChild(box);
  });
}

/* ================= תוצרים ================= */

/* המסננים הם שלוש שורות צ׳יפים. אין תפריט שנפתח, אין אישור, ואין מצב
   ביניים — לחיצה אחת משנה את הרשימה מיד. */
var workRows = [];
var workSig = '';
var pickKind = 'all';
var pickProj = 'all';
var pickWhen = 'all';
var worksFindEl = document.getElementById('worksfind');

var WHENS = [['all', '\(Lang.t("הכל", "all"))'], ['day', '\(Lang.t("היום", "today"))'], ['week', '\(Lang.t("השבוע", "this week"))'], ['month', '\(Lang.t("החודש", "this month"))']];

function pillRow(host, items, current, choose) {
  host.textContent = '';
  items.forEach(function (pair) {
    var pill = el('span', 'pill' + (pair[0] === current ? ' on' : ''), pair[1]);
    pill.addEventListener('click', function () { choose(pair[0]); });
    host.appendChild(pill);
  });
}

function drawSifts(data) {
  var kinds = [['all', '\(Lang.t("הכל", "all"))']];
  var seen = [];
  (data.rows || []).forEach(function (r) {
    if (seen.indexOf(r.kind) < 0) { seen.push(r.kind); }
  });
  seen.sort().forEach(function (k) { kinds.push([k, k]); });

  var projects = [['all', '\(Lang.t("הכל", "all"))']];
  (data.projects || []).forEach(function (p) { projects.push([p, p]); });

  pillRow(document.getElementById('siftkind'), kinds, pickKind,
          function (v) { pickKind = v; drawSifts(data); siftWorks(); });
  pillRow(document.getElementById('siftproj'), projects, pickProj,
          function (v) { pickProj = v; drawSifts(data); siftWorks(); });
  pillRow(document.getElementById('siftwhen'), WHENS, pickWhen,
          function (v) { pickWhen = v; drawSifts(data); siftWorks(); });
}

/* ⛔ Reported 3.10: the outputs list "does not open and close". Each file
   was drawn twice — a row, and under it a card bar with its own button —
   and the whole list was torn down and rebuilt whenever any file anywhere
   changed (every ~20s on a busy day), so whatever you had open jumped away.
   ⇒ One element per file: the card bar *is* the row. Nodes are kept by
   path across repaints and only reordered, so an open file stays open. */
var workNodes = {};

function workCard(item) {
  var card = el('div', 'card shut workcard');
  card.__extra = ' workcard';
  card.appendChild(el('div', 'cardbar'));
  card.appendChild(el('div', 'cardbody'));
  card.__meta = item;
  card.firstChild.addEventListener('click', function () {
    if (isPage(item.path)) { send('reveal', { path: item.path }); return; }
    toggleCard(item.path);
  });
  return card;
}

var SPANS = { day: '\(Lang.t("היום", "Today"))', week: '\(Lang.t("השבוע", "This week"))',
              month: '\(Lang.t("החודש", "This month"))', old: '\(Lang.t("קודם", "Earlier"))' };
var workDays = [];

function buildWorks(rows) {
  var host = document.getElementById('workslist');
  var keep = {};
  workRows = [];
  workDays.forEach(function (d) { d.node.remove(); });
  workDays = [];
  var lastSpan = '';
  rows.forEach(function (item) {
    /* Reported 7.10: "hard to find my way". 500 files in one flat run read
       as a wall. A heading per period gives the eye somewhere to land. */
    if (item.span !== lastSpan) {
      lastSpan = item.span;
      var head = el('div', 'workday', SPANS[item.span] || '');
      host.appendChild(head);
      workDays.push({ node: head, span: item.span });
    }
    var card = workNodes[item.path] || workCard(item);
    card.__meta = item;
    workNodes[item.path] = card;
    keep[item.path] = true;
    host.appendChild(card);          /* moves an existing node; state survives */
    renderCard(item.path);
    workRows.push({ row: card, card: card, item: item,
                    hay: (item.name + ' ' + item.project + ' ' + (item.folder || '')).toLowerCase() });
  });
  Object.keys(workNodes).forEach(function (path) {
    if (!keep[path]) { workNodes[path].remove(); delete workNodes[path]; }
  });
}

function siftWorks() {
  var needle = worksFindEl.value.trim().toLowerCase();
  var live = 0;
  var liveSpans = {};
  workRows.forEach(function (w) {
    var on = (pickKind === 'all' || w.item.kind === pickKind)
          && (pickProj === 'all' || w.item.project === pickProj)
          && (pickWhen === 'all' || w.item.span === pickWhen
              || (pickWhen === 'week' && w.item.span === 'day')
              || (pickWhen === 'month' && (w.item.span === 'day' || w.item.span === 'week')))
          && (!needle || w.hay.indexOf(needle) >= 0);
    w.card.style.display = on ? '' : 'none';
    if (on) { live++; liveSpans[w.item.span] = true; }
  });
  workDays.forEach(function (d) { d.node.className = 'workday' + (liveSpans[d.span] ? '' : ' gone'); });
  document.getElementById('workscount').textContent = live + '\(Lang.t(" תוצרים", " artifacts"))';
}

function paintWorks(data) {
  var rows = data.rows || [];
  var sig = rows.map(function (r) { return r.path + r.age; }).join('|');
  if (sig !== workSig) {
    workSig = sig;
    cardsEnabled = true;
    buildWorks(rows);
    drawSifts(data);
  }
  siftWorks();
}

worksFindEl.addEventListener('input', siftWorks);
/* Enter opens the first file that is still showing. Nothing showing ⇒ the
   words go to the finder, which searches every file and asks the model. */
worksFindEl.addEventListener('keydown', function (e) {
  if (e.key !== 'Enter') { return; }
  e.preventDefault();
  var first = workRows.filter(function (w) { return w.card.style.display !== 'none'; })[0];
  var q = worksFindEl.value.trim();
  if (first && q) { openFile(first.item.path); }
  else if (q) { send('findHere', { text: q }); }
});
document.getElementById('worksmart').addEventListener('click', function () {
  send('findHere', { text: worksFindEl.value.trim() });
});

/* ================= ספר־היכולות ================= */

/* הרשימה נבנית פעם אחת ומסוננת במקום. בנייה מחדש בכל הקלדה הייתה
   מאבדת את השורות שנפתחו, ואת מיקום־הגלילה. */
var bookRows = [];
var bookSig = '';
var siftEl = document.getElementById('booksift');

function buildBook(groups) {
  var host = document.getElementById('booklist');
  host.textContent = '';
  bookRows = [];

  groups.forEach(function (group) {
    var box = el('section', 'fam');
    var head = el('div', 'famhead');
    head.appendChild(el('h4', null, group.title));
    head.appendChild(el('em', null, group.rows.length));
    head.appendChild(document.createElement('hr'));
    box.appendChild(head);

    group.rows.forEach(function (item) {
      var row = el('div', 'skill');
      row.appendChild(el('span', 'nm', item.name));
      row.appendChild(el('span', 'kd', item.kind));
      row.appendChild(el('span', 'hn', item.hint));
      row.addEventListener('click', function () {
        row.className = row.className.indexOf('open') >= 0 ? 'skill' : 'skill open';
      });
      box.appendChild(row);
      bookRows.push({ node: row, group: box,
                      hay: (item.name + ' ' + item.kind + ' ' + item.hint + ' ' +
                            group.title).toLowerCase() });
    });

    host.appendChild(box);
  });
}

function siftBook() {
  var needle = siftEl.value.trim().toLowerCase();
  var live = 0;
  var seen = [];
  bookRows.forEach(function (row) {
    var on = !needle || row.hay.indexOf(needle) >= 0;
    var open = row.node.className.indexOf('open') >= 0;
    row.node.className = on ? (open ? 'skill open' : 'skill') : 'skill gone';
    if (on) { live++; if (seen.indexOf(row.group) < 0) { seen.push(row.group); } }
  });
  for (var i = 0; i < bookRows.length; i++) {
    var g = bookRows[i].group;
    g.className = seen.indexOf(g) >= 0 ? 'fam' : 'fam gone';
  }
  document.getElementById('bookcount').textContent =
    needle ? (live + '\(Lang.t(" מתוך ", " of "))' + bookRows.length) : (bookRows.length + '\(Lang.t(" יכולות", " capabilities"))');
}

function paintBook(groups) {
  var sig = groups.length + ':' + groups.map(function (g) { return g.rows.length; }).join(',');
  if (sig !== bookSig) { bookSig = sig; buildBook(groups); siftBook(); }
  if (document.activeElement !== siftEl) { siftEl.focus(); }
}

siftEl.addEventListener('input', siftBook);

/* ================= סוכני־הרקע ================= */

function paintCrew(crew) {
  var running = crew.filter(function (a) { return a.state === 'run'; }).length;
  var head = document.getElementById('crewcount');
  head.textContent = '';
  head.style.marginInlineStart = 'auto';
  head.style.display = 'flex';
  head.style.gap = '18px';
  head.appendChild(stat('run', running, '\(Lang.t("רצים", "running"))'));
  head.appendChild(stat('', crew.length, 'אחרונים'));

  var host = document.getElementById('crewlist');
  host.textContent = '';
  if (!crew.length) {
    var none = el('div', null, '\(Lang.t("אף סוכן לא רץ ולא רץ לאחרונה.", "No agent is running, and none ran recently."))');
    none.id = 'empty';
    host.appendChild(none);
    return;
  }

  crew.forEach(function (a) {
    var row = el('div', 'crew ' + a.state);

    var lamp = el('div', 'lamp');
    lamp.appendChild(el('span', 'bulb'));
    lamp.appendChild(el('span', 'state', a.stateLabel));
    row.appendChild(lamp);

    row.appendChild(el('div', 'task', a.task));

    var tail = el('div', 'tail');
    // ⇒ סוכן שרץ נמדד במשך ובעבודה שהוא עושה עכשיו; סוכן שסיים — במתי זז
    if (a.state === 'run' && a.doing) {
      var now = el('span', null, a.doing);
      now.style.color = 'var(--run)';
      tail.appendChild(now);
      tail.appendChild(el('span', 'sep', '·'));
    }
    if (a.context) {
      tail.appendChild(el('span', null, a.context));
      tail.appendChild(el('span', 'sep', '·'));
    }
    if (a.model) { tail.appendChild(el('span', null, a.model)); }
    tail.appendChild(el('span', 'sep', '·'));
    tail.appendChild(el('span', 'age', a.state === 'run' ? a.since : a.age));
    row.appendChild(tail);

    var from = el('div', 'from');
    from.appendChild(el('span', 'type', a.kind));
    from.appendChild(el('span', 'sep', '·'));
    from.appendChild(el('span', null, a.chat));
    if (a.depth > 1) {
      from.appendChild(el('span', 'sep', '·'));
      from.appendChild(el('span', null, '\(Lang.t("סוכן של סוכן", "agent of an agent"))'));
    }
    row.appendChild(from);

    row.addEventListener('click', function () { send('open', { sid: a.sid }); });
    host.appendChild(row);
  });
}

/* ================= חיפוש ================= */

document.getElementById('logo').appendChild(markNode(30));

var findEl = document.getElementById('find');
var findTimer = null;

var searchQuery = '';
function paintSearch(search) {
  searchQuery = search.query || '';
  var count = document.getElementById('findcount');
  count.textContent = '';
  var busy = search.building > 0 || search.busy;
  if (busy) { count.appendChild(spinner(15)); setPace(2); }
  count.appendChild(el('span', null,
      search.building ? ('\(Lang.t("בונה אינדקס · ", "Building index · "))' + search.building + '\(Lang.t(" יומנים", " logs"))')
    : (search.busy ? '\(Lang.t("מחפש…", "searching…"))'
    : (search.query.length < 2 ? '\(Lang.t("שתי אותיות לפחות", "At least two letters"))'
    : (((search.files || []).length) + '\(Lang.t(" קבצים · ", " files · "))' + search.hits.length + '\(Lang.t(" שיחות", " conversations"))')))));

  var host = document.getElementById('hits');
  host.textContent = '';

  /* The small model's picks come first, each with its one-line reason. */
  if (search.smartBusy || search.smartFailed || (search.smart && search.smart.length) || search.smartQuery) {
    var sm = el('div', 'smartbox');
    var sh = el('div', 'smarthead');
    sh.appendChild(el('span', null, '\(Lang.t("לפי משמעות: ", "By meaning: "))' + (search.smartQuery || '')));
    if (search.smartBusy) { sh.appendChild(spinner(13)); }
    sm.appendChild(sh);
    if (search.smartFailed) {
      sm.appendChild(el('div', 'smartnote', '\(Lang.t("המודל לא ענה. החיפוש הרגיל למטה עדיין עובד.", "The model did not answer. The normal search below still works."))'));
    } else if (!search.smartBusy && !(search.smart || []).length) {
      sm.appendChild(el('div', 'smartnote', '\(Lang.t("לא נמצאה שיחה מתאימה", "No matching conversation"))'));
    }
    (search.smart || []).forEach(function (c) { sm.appendChild(c.file ? fileHit(c) : hitCard(c)); });
    host.appendChild(sm);
  }
  /* Names first — a file or a conversation whose name has the words. */
  if ((search.files || []).length) {
    host.appendChild(el('div', 'findsec', '\(Lang.t("קבצים", "Files"))'));
    search.files.forEach(function (f) { host.appendChild(fileHit(f)); });
  }
  if ((search.titles || []).length) {
    host.appendChild(el('div', 'findsec', '\(Lang.t("שיחות לפי שם", "Conversations by name"))'));
    search.titles.forEach(function (c) { host.appendChild(hitCard(c)); });
  }
  if ((search.hits || []).length) {
    host.appendChild(el('div', 'findsec', '\(Lang.t("בתוך השיחות", "Inside conversations"))'));
  }
  /* ⛔ **רשימה שטוחה של ציטוטים אינה ניתנת לפענוח.** אותה שיחה חזרה חמש
     פעמים, בלי שם, ובלי דרך לדעת על מה ללחוץ. ⇒ שיחה אחת = כרטיס אחד,
     עם השם שלה בראש והשורות שנמצאו בה תחתיו. */
  (search.hits || []).forEach(function (c) { host.appendChild(hitCard(c)); });
}

function hitCard(c) {
    var card = el('div', 'hitchat');

    var head = el('div', 'hithead');
    head.appendChild(el('span', 'hitname', c.title));
    if (c.project) { head.appendChild(el('span', 'hitproj', c.project)); }
    head.appendChild(el('span', 'hitwhen', c.when));
    head.appendChild(el('span', 'hitopen', '\(Lang.t("לקרוא", "Read"))'));
    var go = el('span', 'hitopen hitresume', '\(Lang.t("להמשיך במסוף", "Continue in terminal"))');
    go.addEventListener('click', function (e) { e.stopPropagation(); send('resume', { sid: c.sid }); });
    head.appendChild(go);
    card.appendChild(head);
    if (c.why) { card.appendChild(el('div', 'hitwhy', c.why)); }

    (c.hits || []).forEach(function (h) {
      var line = el('div', 'hitline ' + h.role);
      /* Each quoted line opens the conversation at that very message. */
      line.addEventListener('click', function (e) {
        e.stopPropagation();
        send('open', { sid: c.sid, find: { query: searchQuery, ts: h.sort || 0, role: h.role } });
      });
      line.appendChild(el('span', 'hitwho', h.role === 'you' ? '\(Lang.t("אתה", "You"))' : '\(Lang.t("המסוף", "Terminal"))'));
      var body = el('span', 'hittext');
      body.appendChild(document.createTextNode(h.before));
      body.appendChild(el('mark', null, h.hit));
      body.appendChild(document.createTextNode(h.after));
      line.appendChild(body);
      card.appendChild(line);
    });

    if (c.total > (c.hits || []).length) {
      card.appendChild(el('div', 'hitmore',
        '\(Lang.t("ועוד ", "and "))' + (c.total - c.hits.length) + '\(Lang.t(" באותה שיחה", " in the same conversation"))'));
    }

    card.addEventListener('click', function () {
      /* The card opens at its newest quoted line; a name or meaning match has
         no line, and only marks the words (the meaning search's question is a
         sentence, not words to mark). */
      var h0 = (c.hits || [])[0];
      if (h0) { send('open', { sid: c.sid, find: { query: searchQuery, ts: h0.sort || 0, role: h0.role } }); }
      else if (!c.why && searchQuery.length >= 2) { send('open', { sid: c.sid, find: { query: searchQuery, ts: 0, role: '' } }); }
      else { send('open', { sid: c.sid }); }
    });
    return card;
}


var TEXTISH = ['md', 'markdown', 'txt', 'json', 'csv', 'tsv', 'py', 'js', 'sh', 'swift', 'css', 'yml', 'yaml', 'log', 'php'];

/* A file opens where it reads best: text in Peach's reader, pages and
   images in their own app. */
function openFile(path) {
  if (TEXTISH.indexOf(extOf(path)) >= 0) { send('openDoc', { path: path, reader: true }); }
  else { send('reveal', { path: path }); }
}

function fileHit(f) {
  var row = el('div', 'filehit');
  row.appendChild(el('span', 'fn', f.name));
  row.appendChild(el('span', 'fd', f.folder || f.project || ''));
  row.appendChild(el('span', 'fk', f.kind || ''));
  row.appendChild(el('span', 'fa', f.age || ''));
  if (f.why) { row.appendChild(el('div', 'fw', f.why)); }
  var where = el('span', 'fo', '\(Lang.t("להראות בתיקייה", "Show in folder"))');
  where.addEventListener('click', function (e) { e.stopPropagation(); send('showInFinder', { path: f.path }); });
  row.insertBefore(where, row.children[3]);
  row.addEventListener('click', function () { openFile(f.path); });
  return row;
}

function smartGo() {
  var q = findEl.value.trim();
  if (q.length >= 3) { send('smartSearch', { text: q }); }
}

/* The model also runs by itself once you stop typing a description —
   two words or more. One word is a name, and the name search has it. */
var smartTimer = null;
function smartSoon() {
  if (smartTimer) { clearTimeout(smartTimer); }
  var q = findEl.value.trim();
  if (q.split(' ').filter(function (w) { return w.length > 1; }).length < 2) { return; }
  smartTimer = setTimeout(smartGo, 1100);
}

function focusFind() {
  setTimeout(function () { findEl.focus(); findEl.select(); }, 60);
}
function setFind(text) {
  findEl.value = text;
  focusFind();
}
document.getElementById('smartgo').addEventListener('click', smartGo);
/* ⌘↩ in the search field asks the model; plain typing stays word search. */
findEl.addEventListener('keydown', function (e) {
  /* Enter asks the model; the word search already runs as you type. */
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (smartTimer) { clearTimeout(smartTimer); }
    smartGo();
  }
});

findEl.addEventListener('input', function () {
  if (findTimer) { clearTimeout(findTimer); }
  findTimer = setTimeout(function () { send('search', { text: findEl.value }); }, 200);
  smartSoon();
});

/* ================= שיחה ================= */

var rackRows = [];
var rackPick = -1;

function markPick() {
  rackRows.forEach(function (row, i) {
    var base = row.className.replace(' pick', '');
    row.className = i === rackPick ? base + ' pick' : base;
  });
  if (rackPick >= 0 && rackRows[rackPick]) {
    rackRows[rackPick].scrollIntoView({ block: 'nearest' });
  }
}

/* ================= חוגת־המספרים ================= */
/* ‏**ספרה במקלדת פותחת את המסוף שמספרו כך.** מספר־העמדה הוא הדבר הראשון
   שהעין תופסת בשורה, ולכן הוא גם הדרך המהירה ביותר להגיע אליה.

   ⛔ ‏**ספרה בודדת אינה תשובה סופית.** במדף שיש בו 2 ו-20, הקשה על "2"
      אינה יכולה לפתוח מיד — היא גם תחילתו של 20. לכן הספרות נאספות
      לחוגה: פתיחה מיידית רק כשאין מספר ארוך יותר שמתחיל באותן ספרות,
      ואחרת המתנה קצרה לספרה הבאה. */

var rackSlots = [];
var dialBuf = '';
var dialTimer = null;
var DIAL_WAIT = 900;

function dialClear() {
  dialBuf = '';
  if (dialTimer) { clearTimeout(dialTimer); dialTimer = null; }
  showDial();
}

/* המספר כפי שהוא נקרא: "007" ו-"7" הם אותו מסוף */
function dialNum() { return dialBuf.replace(/^0+/, ''); }

function dialExact() {
  var want = dialNum();
  if (!want) { return []; }
  return rackSlots.filter(function (r) { return r.num === want; });
}

function dialDeeper() {
  var want = dialNum();
  if (!want) { return rackSlots; }
  return rackSlots.filter(function (r) {
    return r.num.length > want.length && r.num.indexOf(want) === 0;
  });
}

function showDial() {
  var box = document.getElementById('dial');
  if (!dialBuf) {
    box.className = '';
    // ⛔ בלי הניקוי הזה הסימון נשאר על המדף: הציור אינו חוזר כשדבר לא השתנה,
    //    ולכן שורות מסומנות היו יכולות להישאר כך עד הפעימה הבאה שמשנה משהו.
    rackRows.forEach(function (row) { row.className = row.className.replace(' aim', ''); });
    return;
  }
  var hit = dialExact();
  var deeper = dialDeeper();
  var miss = !hit.length && !deeper.length;
  box.className = 'on' + (miss ? ' miss' : '');
  box.querySelector('.digits').textContent = dialBuf;
  box.querySelector('.what').textContent =
      miss ? '\(Lang.t("אין מסוף כזה", "No such terminal"))'
    : (hit.length ? hit[0].title
    : (dialNum() ? (deeper.length + '\(Lang.t(" מסופים מתחילים כך", " terminals start this way"))') : '\(Lang.t("ממתין לספרה", "waiting for a digit"))'));

  // סימון על המדף עצמו, כדי שברור לאן הולכים לפני שנפתח
  var aimed = hit.concat(deeper);
  rackRows.forEach(function (row, i) {
    var base = row.className.replace(' aim', '');
    row.className = aimed.indexOf(rackSlots[i]) >= 0 ? base + ' aim' : base;
  });
}

function dialOpen(row) {
  dialClear();
  send('open', { sid: row.sid });
}

function dialFeed(digit) {
  if (dialTimer) { clearTimeout(dialTimer); dialTimer = null; }
  dialBuf += digit;
  var hit = dialExact();
  var deeper = dialDeeper();
  showDial();
  // אין המשך אפשרי ויש התאמה אחת ⇒ אין על מה לחכות
  if (hit.length === 1 && !deeper.length) { dialOpen(hit[0]); return; }
  if (!hit.length && !deeper.length) {
    dialTimer = setTimeout(dialClear, 700);
    return;
  }
  dialTimer = setTimeout(function () {
    var now = dialExact();
    if (now.length === 1) { dialOpen(now[0]); } else { dialClear(); }
  }, DIAL_WAIT);
}

/* היסטוריית־השורה, כמו במסוף: חץ־למעלה בשדה ריק מחזיר את מה שאמרת
   קודם. הטיוטה נשמרת ומוחזרת באסקייפ, כדי שאפשר יהיה לצאת בלי לאבד. */
/* ⛔ אסור לקרוא למשתנה הזה `history`. בדפדפן `window.history` הוא נכס
   **לקריאה בלבד**, ו-`var history` בראש המסמך אינו יוצר משתנה חדש אלא
   נתלה על הקיים. ⇒ ההשמה זרקה `TypeError: Attempted to assign to
   readonly property`, **וכל פונקציית־הציור נפלה איתה בכל פעימה** —
   המסך נשאר שחור לגמרי. והקריאות דווקא עבדו בשקט, כי ל-`window.history`
   יש `length` משלו. נמדד 25.8.2026 ביומן־הריצה, שורה 1337 במסמך. */
var typed = [];
var histAt = -1;
var histDraft = '';

function walkHistory(step) {
  if (!typed.length) { return false; }
  if (histAt < 0) { histDraft = fieldEl.value; }
  var next = histAt + step;
  if (next < -1) { next = -1; }
  if (next >= typed.length) { next = typed.length - 1; }
  histAt = next;
  fieldEl.value = histAt < 0 ? histDraft : typed[histAt];
  fieldEl.selectionStart = fieldEl.selectionEnd = fieldEl.value.length;
  return true;
}

function resetHistory() { histAt = -1; histDraft = ''; }

var lastKey = '';
var MODELS = [
  { id: '', label: 'מודל' },
  { id: 'opus', label: '\(Lang.t("אופוס", "Opus"))' },
  { id: 'sonnet', label: '\(Lang.t("סונט", "Sonnet"))' },
  { id: 'haiku', label: '\(Lang.t("הייקו", "Haiku"))' },
  { id: 'default', label: '\(Lang.t("ברירת־מחדל", "default"))' }
];

var modelEl = document.getElementById('modelpick');
MODELS.forEach(function (m) {
  var o = document.createElement('option');
  o.value = m.id;
  o.textContent = m.label;
  modelEl.appendChild(o);
});
modelEl.addEventListener('change', function () {
  var id = modelEl.value;
  modelEl.value = '';
  if (id) { send('send', { text: '/model ' + id }); }
});

/* מי שואל אותך במקום אחר. נשלח בכל פעימה שבה יש שיחה פתוחה. */
function paintAlerts(list) {
  var host = document.getElementById('alerts');
  host.textContent = '';
  if (!list || !list.length) { host.className = ''; return; }
  host.className = 'on';
  host.appendChild(el('span', 'lead',
    list.length === 1 ? '\(Lang.t("מסוף אחר שואל אותך", "Another terminal is asking you"))' : list.length + '\(Lang.t(" מסופים שואלים אותך", " terminals asking you"))'));
  list.forEach(function (a) {
    var chip = el('div', 'who');
    chip.appendChild(el('b', null, a.slot));
    chip.appendChild(el('span', 'what', a.question || a.head));
    chip.title = '\(Lang.t("לפתוח את השיחה הזאת", "Open this conversation"))';
    chip.addEventListener('click', function () { send('open', { sid: a.sid }); });
    host.appendChild(chip);
  });
}

/* ================= התוצרים של השיחה ================= */

/* The conversation's own files, oldest first and numbered, under one button
   in the bar. Each is the same card as everywhere else: opens in place,
   edits, goes full-window. Open/closed is remembered across launches. */
var outsOpen = false;
try { outsOpen = localStorage.getItem('outsOpen') === '1'; } catch (e) {}
var outsSig = '';

function paintOutputs(list) {
  list = list || [];
  var btn = document.getElementById('outsbtn');
  var host = document.getElementById('outs');
  btn.style.display = list.length ? '' : 'none';
  btn.textContent = (outsOpen ? '▾ ' : '▸ ') + '\(Lang.t("תוצרים", "Outputs"))' + ' ' + list.length;
  btn.className = 'btn' + (outsOpen ? ' on' : '');
  host.className = outsOpen && list.length ? 'on' : '';
  var sig = list.map(function (o) { return o.path + o.size; }).join('|');
  if (sig === outsSig) { return; }
  outsSig = sig;
  var keep = {};
  list.forEach(function (o) {
    var card = outNodes[o.path];
    if (!card) {
      card = el('div', 'card shut workcard outcard');
      card.__extra = ' workcard outcard';
      card.appendChild(el('div', 'cardbar'));
      card.appendChild(el('div', 'cardbody'));
      (function (path) {
        card.firstChild.addEventListener('click', function () {
          if (isPage(path)) { send('reveal', { path: path }); return; }
          toggleCard(path);
        });
      })(o.path);
      outNodes[o.path] = card;
    }
    card.__meta = { kind: o.n + ' · ' + o.kind, when: o.when, size: o.size };
    keep[o.path] = true;
    host.appendChild(card);
    renderCard(o.path);
  });
  Object.keys(outNodes).forEach(function (path) {
    if (!keep[path]) { outNodes[path].remove(); delete outNodes[path]; }
  });
}

document.getElementById('outsbtn').addEventListener('click', function () {
  outsOpen = !outsOpen;
  try { localStorage.setItem('outsOpen', outsOpen ? '1' : '0'); } catch (e) {}
  outsSig = '';
  paintOutputs(lastOutputs);
});
var lastOutputs = [];

var lastAskSeen = '';
var lastChatSid = '';
var lastTailSig = '';

/* ================= Search marks inside a conversation =================
   Requested 10.10: a search result opens its conversation at the very
   message, with every occurrence of the words marked and a bar to step
   through them (⌘G / ⇧⌘G, Esc clears).
   - Matching folds Hebrew points and cantillation, invisible direction
     marks and runs of white space, and ignores Latin case — the same text
     the index searched, as the eye sees it.
   - Marks are plain inline <mark> runs inside the existing text, so the
     bidi order of every line is untouched.
   - The log is rebuilt on refreshes; the marks are re-applied each time and
     the current match is kept by its block and its place in the block. */
var FIND = null;          /* {sid, query, ts, role, token, ready} from Peach */
var findMarks = [];       /* one entry per match: [mark elements] */
var findAt = -1;
var findBuildDone = -1;   /* logBuild the marks were applied to */
var findTokenDone = -1;   /* token whose scroll-to-target already happened */
var findKeep = null;      /* {k, n} of the current match, across rebuilds */
var findAtStart = true;
var logBuild = 0;
var FOLD_SKIP = /[\\u0591-\\u05BD\\u05BF\\u05C1\\u05C2\\u05C4\\u05C5\\u05C7\\u200B-\\u200F\\u202A-\\u202E\\u2066-\\u2069\\u00AD]/;
var BLOCK_TAGS = { P: 1, DIV: 1, LI: 1, TD: 1, TH: 1, PRE: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, TR: 1, BLOCKQUOTE: 1, UL: 1, OL: 1, TABLE: 1 };

/* text → {s: folded, map: index of each folded char in the original} */
function foldText(text) {
  var out = '', map = [], space = false;
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i);
    if (FOLD_SKIP.test(ch)) { continue; }
    if (/\\s/.test(ch)) {
      if (space) { continue; }
      space = true; out += ' '; map.push(i); continue;
    }
    space = false;
    var lc = ch.toLowerCase();
    out += lc.length === 1 ? lc : ch;
    map.push(i);
  }
  return { s: out, map: map };
}

function findOn() {
  return !!FIND && document.getElementById('chatview').className.indexOf(' on') >= 0;
}

function findSkip(node) {
  for (var p = node.parentNode; p && p.id !== 'log'; p = p.parentNode) {
    if (!p.classList) { continue; }
    if (p.classList.contains('card') || p.classList.contains('chip') || p.classList.contains('fhit') || p.tagName === 'TEXTAREA'
        || p.tagName === 'BUTTON' || p.tagName === 'SCRIPT' || p.tagName === 'STYLE') { return true; }
  }
  return false;
}

function blockOf(node) {
  for (var p = node.parentNode; p; p = p.parentNode) { if (BLOCK_TAGS[p.tagName]) { return p; } }
  return null;
}

function clearMarks() {
  document.querySelectorAll('#log mark.fhit').forEach(function (m) {
    var parent = m.parentNode;
    while (m.firstChild) { parent.insertBefore(m.firstChild, m); }
    parent.removeChild(m);
    parent.normalize();
  });
  findMarks = [];
}

/* Mark every occurrence of one folded needle in one message body. */
function markBody(body, needle, matchList) {
  var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null);
  var nodes = [], node;
  while ((node = walker.nextNode())) { if (!findSkip(node)) { nodes.push(node); } }
  if (!nodes.length) { return; }
  /* One folded string over the whole body; a virtual space between blocks
     so "end of a paragraph" + "start of the next" never fakes a match. */
  var full = '', where = [], lastBlock = null;
  nodes.forEach(function (n, ni) {
    var b = blockOf(n);
    if (ni > 0 && b !== lastBlock && full.charAt(full.length - 1) !== ' ') { full += ' '; where.push(null); }
    lastBlock = b;
    var f = foldText(n.nodeValue);
    for (var i = 0; i < f.s.length; i++) {
      if (f.s.charAt(i) === ' ' && full.charAt(full.length - 1) === ' ') { continue; }
      full += f.s.charAt(i); where.push([ni, f.map[i]]);
    }
  });
  var segs = [];   /* [nodeIndex, start, end, matchNo] */
  var from = 0, at;
  while ((at = full.indexOf(needle, from)) >= 0) {
    var no = matchList.length;
    matchList.push([]);
    var cur = null;
    for (var j = at; j < at + needle.length; j++) {
      var w = where[j];
      if (!w) { continue; }
      if (cur && cur[0] === w[0]) { cur[2] = w[1] + 1; }
      else { cur = [w[0], w[1], w[1] + 1, no]; segs.push(cur); }
    }
    from = at + needle.length;
  }
  /* Extend each segment over skipped points that sit inside it. */
  /* Split from the end of each node so earlier offsets stay valid. */
  segs.sort(function (a, b) { return a[0] !== b[0] ? a[0] - b[0] : b[1] - a[1]; });
  segs.forEach(function (sg) {
    var n = nodes[sg[0]];
    var text = n.nodeValue;
    var end = sg[2];
    while (end < text.length && FOLD_SKIP.test(text.charAt(end))) { end++; }
    var mid = n.splitText(sg[1]);
    mid.splitText(end - sg[1]);
    var m = document.createElement('mark');
    m.className = 'fhit';
    mid.parentNode.insertBefore(m, mid);
    m.appendChild(mid);
    matchList[sg[3]].unshift(m);
  });
}

function applyMarks() {
  clearMarks();
  if (!FIND) { return; }
  var q = foldText(String(FIND.query || '').trim()).s;
  if (q.length < 2) { return; }
  var bodies = Array.prototype.slice.call(document.querySelectorAll('#log .turn .body'));
  var list = [];
  bodies.forEach(function (b) { markBody(b, q, list); });
  /* A name match may not have the phrase in the text: then its words. */
  if (!list.length && q.indexOf(' ') > 0) {
    q.split(' ').filter(function (w) { return w.length >= 2; }).forEach(function (w) {
      bodies.forEach(function (b) { markBody(b, w, list); });
    });
  }
  /* Document order, top to bottom. */
  list = list.filter(function (x) { return x.length; });
  list.sort(function (a, b) {
    return a[0].compareDocumentPosition(b[0]) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
  });
  findMarks = list;
}

function turnOf(m) {
  for (var p = m.parentNode; p; p = p.parentNode) { if (p.classList && p.classList.contains('turn')) { return p; } }
  return null;
}

function keyOf(i) {
  var t = turnOf(findMarks[i][0]);
  if (!t) { return null; }
  var n = 0;
  for (var j = i - 1; j >= 0 && turnOf(findMarks[j][0]) === t; j--) { n++; }
  return { k: t.dataset.k, n: n };
}

/* The clicked message: same speaker, same second (the index keeps whole
   seconds), and the first occurrence in it — the one the result quoted. */
function targetIndex() {
  var ts = Number(FIND.ts || 0);
  if (!(ts > 0)) { return findMarks.length - 1; }
  var best = -1, bestGap = 1e12;
  findMarks.forEach(function (m, i) {
    var t = turnOf(m[0]);
    if (!t) { return; }
    var gap = Math.abs(Number(t.dataset.ts || 0) - ts);
    if (FIND.role && t.dataset.role !== FIND.role) { gap += 5; }
    if (gap < bestGap) { bestGap = gap; best = i; }
  });
  return best;
}

function centerOn(m) {
  revealFolded(m);
  var box = document.getElementById('logscroll');
  var br = box.getBoundingClientRect(), r = m.getBoundingClientRect();
  stickBottom = false;
  hidePill();
  box.scrollTop = box.scrollTop + (r.top - br.top) - (box.clientHeight / 2 - r.height / 2);
  placedTop = box.scrollTop;
  captureAnchor();
}

function showCurrent(scroll) {
  findMarks.forEach(function (ms, i) {
    ms.forEach(function (m) { m.className = 'fhit' + (i === findAt ? ' now' : ''); });
  });
  findKeep = findAt >= 0 ? keyOf(findAt) : null;
  if (scroll && findAt >= 0) { centerOn(findMarks[findAt][0]); }
  paintFindBar();
}

function paintFindBar() {
  var bar = document.getElementById('chatfind');
  if (!FIND) { bar.className = ''; return; }
  bar.className = 'on';
  bar.querySelector('.fq').textContent = FIND.query;
  var n = bar.querySelector('.fn');
  if (!findMarks.length) {
    n.textContent = (FIND.ready ? '\(Lang.t("לא נמצא בחלק שנטען", "Not in the loaded part"))' : '\(Lang.t("טוען…", "loading…"))');
  } else {
    n.textContent = (findAt + 1) + ' \(Lang.t("מתוך", "of")) ' + findMarks.length + (findAtStart ? '' : '+');
    n.title = findAtStart ? '' : '\(Lang.t("יש עוד למעלה — ▲ טוען מוקדם יותר", "More above — ▲ loads earlier"))';
  }
}

/* Called on every paint of the chat view. */
function syncFind(find, chat) {
  var was = FIND;
  FIND = find;
  findAtStart = !!(chat && chat.atStart);
  if (!FIND) {
    if (was) { clearMarks(); findAt = -1; findKeep = null; }
    paintFindBar();
    return;
  }
  var fresh = !was || was.token !== FIND.token;
  if (fresh) { findKeep = null; findAt = -1; }
  if (fresh || findBuildDone !== logBuild) {
    applyMarks();
    findBuildDone = logBuild;
    /* Keep the current match across a rebuild. */
    findAt = -1;
    if (findKeep) {
      for (var i = 0; i < findMarks.length; i++) {
        var k = keyOf(i);
        if (k && k.k === findKeep.k && k.n === findKeep.n) { findAt = i; break; }
      }
    }
  }
  if (findTokenDone !== FIND.token && FIND.ready) {
    /* The window must reach the clicked message before we scroll to it:
       the first loaded turn has to be at or before its time. */
    var turns = document.querySelectorAll('#log .turn');
    var firstTs = turns.length ? Number(turns[0].dataset.ts || 0) : 0;
    var reached = !(FIND.ts > 0) || findAtStart || (firstTs > 0 && firstTs <= FIND.ts + 1);
    if (reached) {
      findTokenDone = FIND.token;
      findAt = findMarks.length ? targetIndex() : -1;
      showCurrent(true);
      return;
    }
  }
  if (findAt < 0 && findMarks.length && findTokenDone === FIND.token) { findAt = findMarks.length - 1; }
  showCurrent(false);
}

function findStep(by) {
  if (!FIND || !findMarks.length) { return; }
  if (by < 0 && findAt <= 0 && !findAtStart) { askEarlier(); return; }
  findAt = (findAt + by + findMarks.length) % findMarks.length;
  showCurrent(true);
}

function clearFind() {
  FIND = null;
  clearMarks();
  findAt = -1; findKeep = null;
  paintFindBar();
  send('findClear');
}

document.getElementById('findprev').addEventListener('click', function () { findStep(-1); });
document.getElementById('findnext').addEventListener('click', function () { findStep(1); });
document.getElementById('findclose').addEventListener('click', clearFind);

function paintChat(chat) {
  lastOutputs = chat.outputs || [];
  paintOutputs(lastOutputs);
  typed = chat.history || [];
  document.getElementById('chatslot').textContent = chat.slot;
  /* ⛔ **שם שאינו נשמר אינו שם.** הכותרת שהמודל נותן משתנה מעצמה לאורך
     היום; מה שהמשתמש מקליד כאן גובר עליה ושורד סגירה ופתיחה.
     ⚠ ואין לדרוס בזמן שהוא כותב — ציור־רקע רץ כל שנייה וחצי. */
  var titleEl = document.getElementById('chattitle');
  if (document.activeElement !== titleEl) { titleEl.textContent = chat.title; }
  titleEl.contentEditable = 'true';
  titleEl.spellcheck = false;
  titleEl.dataset.sid = chat.sid;
  titleEl.title = '\(Lang.t("לחיצה משנה את השם · ריק מחזיר את הכותרת האוטומטית", "Click to rename · empty restores the automatic title"))';

  var meta = document.getElementById('chatmeta');
  meta.textContent = '';
  var lamp = el('span', 'state', chat.stateLabel);
  lamp.style.color = chat.state === 'run' ? 'var(--run)'
                   : (chat.state === 'wait' ? 'var(--wait)' : 'var(--idle)');
  meta.appendChild(lamp);
  if (chat.model) { meta.appendChild(el('span', 'sep', '·')); meta.appendChild(el('span', null, chat.model)); }
  if (chat.context) {
    meta.appendChild(el('span', 'sep', '·'));
    var cx = el('span', null, chat.context);
    if (chat.ctxLevel) { cx.style.color = chat.ctxLevel === 'ask' ? 'var(--wait)' : 'var(--peach)'; }
    meta.appendChild(cx);
  }
  /* The same one click as on the rack row, inside the open conversation. */
  if (chat.relay === 'ready' || chat.relay === 'go') {
    meta.appendChild(el('span', 'sep', '·'));
    var rg = el('span', 'btn', chat.relay === 'go' ? '\(Lang.t("ממתין לרגע שקט…", "Waiting for a quiet moment…"))'
                                                  : '\(Lang.t("המשך בשיחה חדשה", "Continue in a new conversation"))');
    rg.style.color = 'var(--peach)';
    rg.style.borderColor = 'var(--peach)';
    if (chat.relay === 'ready') {
      rg.addEventListener('click', function () {
        rg.textContent = '\(Lang.t("ממתין לרגע שקט…", "Waiting for a quiet moment…"))';
        send('relayGo', { sid: chat.sid });
      });
    }
    meta.appendChild(rg);
    if (chat.relayAgents > 0) {
      meta.appendChild(el('span', null, chat.relayAgents + '\(Lang.t(" סוכנים עדיין רצים — את התוצאות שלהם ממשיכים מהמסירה", " agents still running — their results are picked up from the hand-off"))'));
    } else if (chat.relayShell) {
      meta.appendChild(el('span', null, '\(Lang.t("משימות־רקע עדיין רצות — את התוצאות שלהן ממשיכים מהמסירה", "background tasks still running — their results are picked up from the hand-off"))'));
    }
  }

  setPace(chat.state === 'run' ? 2 : 0);
  modelEl.style.display = chat.live ? '' : 'none';
  /* A closed conversation gets one obvious way back: continue it. */
  var raiseBtn = document.getElementById('raise');
  raiseBtn.style.display = '';
  raiseBtn.textContent = chat.live ? '\(Lang.t("לחלון", "To window"))' : '\(Lang.t("להמשיך במסוף", "Continue in terminal"))';
  raiseBtn.className = 'btn' + (chat.live ? '' : ' on');
  resumeSid = chat.live ? '' : chat.sid;

  var composer = document.getElementById('composer');
  composer.className = chat.live ? '' : 'off';
  paintGhost(chat.live ? (chat.suggest || '') : '');
  var target = document.getElementById('target');
  target.textContent = '';
  if (chat.live) {
    target.appendChild(el('span', null, '\(Lang.t("נשלח אל", "Sent to"))'));
    var slot = el('span', null, chat.slot);
    slot.style.direction = 'ltr';
    slot.style.unicodeBidi = 'isolate';
    target.appendChild(slot);
    target.appendChild(el('span', null, chat.title));
  } else {
    // בלי else מפורש כאן הייתה יציאה מוקדמת מכל פונקציית־הציור, ושיחה
    // של מסוף סגור נראתה ריקה לגמרי
    target.appendChild(el('span', null,
      '\(Lang.t("המסוף של השיחה הזאת סגור — אפשר לקרוא, אין לאן לכתוב", "This conversation terminal is closed — you can read, there is nowhere to write"))'));
  }

  paintCrewStrip(chat.crew || []);

  // ציור מחדש בזמן שכרטיס נערך היה מוחק את הטיוטה שבתוכו
  if (editingPath) { return; }

  var key = chat.key || '';
  if (key === lastKey) { return; }
  lastKey = key;

  var scroll = document.getElementById('logscroll');
  // Another conversation opens at its bottom, not at the previous one's position.
  var sameChat = chat.sid === lastChatSid;
  if (!sameChat) {
    lastChatSid = chat.sid;
    stickBottom = true;
    anchor = null;
    lastTailSig = '';
    foldOpen = {};
    hidePill();
  }
  lastAtStart = !!chat.atStart;
  var wasDown = nearBottom();
  // ⇒ המרחק **מהתחתית** נשמר, ולא מלמעלה: כשמוסיפים הודעות מוקדמות יותר
  //   הגובה גדל בראש, ועיגון לפי scrollTop היה מקפיץ את הקריאה למקום אחר.
  var fromBottom = scroll.scrollHeight - scroll.scrollTop;

  var log = document.getElementById('log');
  log.textContent = '';

  var earlier = el('div', chat.atStart ? 'done' : null);
  earlier.id = 'earlier';
  if (chat.atStart) {
    earlier.appendChild(el('hr'));
    earlier.appendChild(el('span', null, '\(Lang.t("תחילת השיחה", "Start of the conversation"))'));
    earlier.appendChild(el('hr'));
  } else {
    earlier.appendChild(el('b', null, '↑'));
    earlier.appendChild(el('span', null, '\(Lang.t("להראות מוקדם יותר", "Show earlier"))'));
    earlier.appendChild(el('hr'));
    earlier.addEventListener('click', askEarlier);
  }
  log.appendChild(earlier);
  logBuild += 1;
  cardNodes = {};
  cardsEnabled = true;
  // A stable name for every block, so the reading position survives the rebuild.
  var seenKeys = {};
  var tailSig = '';
  function blockKey(line) {
    var base = line.role + '|' + (line.pending ? 'p' : line.when) + '|'
      + String(line.text || '').slice(0, 160) + '|' + (line.arg || '');
    seenKeys[base] = (seenKeys[base] || 0) + 1;
    return base + '#' + seenKeys[base];
  }
  // Collapsed view: every block after one of the user's messages belongs to that
  // message's answer (data-g = the message's block key). Blocks before the
  // first loaded message get a synthetic head ("continued from above").
  var foldKey = '';
  var foldHead = null;
  function foldMember(node, isTool) {
    if (!foldHead) {
      foldKey = 'orphan';
      foldHead = el('div', 'foldhead');
      foldHead.dataset.k = 'orphan';
      foldHead.dataset.g = 'orphan';
      foldHead.dataset.acts = '0';
      foldHead.dataset.says = '0';
      foldHead.appendChild(el('span', null, '\(Lang.t("↑ המשך תשובה מלמעלה", "↑ continued answer from above"))'));
      foldHead.appendChild(el('span', 'foldsum'));
      foldHead.addEventListener('click', function () { toggleGroup('orphan'); });
      log.appendChild(foldHead);
    }
    node.dataset.g = foldKey;
    if (isTool) { foldHead.dataset.acts = String(Number(foldHead.dataset.acts) + 1); }
    else { foldHead.dataset.says = String(Number(foldHead.dataset.says) + 1); }
  }
  (chat.lines || []).forEach(function (line) {
    var bk = blockKey(line);
    tailSig = bk + '|' + String(line.text || '').length;
    if (line.role === 'tool') {
      var act = el('div', 'act');
      act.dataset.k = bk;
      act.appendChild(el('span', 'tick'));
      act.appendChild(el('span', 'what', line.text));
      if (line.arg) {
        act.appendChild(el('span', 'sep', '·'));
        act.appendChild(el('span', 'arg', line.arg));
      }
      foldMember(act, true);
      log.appendChild(act);
      return;
    }
    var turn = el('div', 'turn ' + line.role + (line.pending ? ' pending' : ''));
    turn.dataset.k = bk;
    turn.dataset.ts = String(line.ts || 0);
    turn.dataset.role = line.role;
    var who = el('div', 'who');
    who.appendChild(el('span', null, line.role === 'you' ? '\(Lang.t("אתה", "You"))' : '\(Lang.t("המסוף", "Terminal"))'));
    who.appendChild(el('span', 'when', line.pending ? '\(Lang.t("נשלח…", "sending…"))' : line.when));
    turn.appendChild(who);
    if (line.role === 'you') {
      // This message heads a new answer group.
      foldKey = bk;
      foldHead = turn;
      turn.dataset.g = bk;
      turn.dataset.acts = '0';
      turn.dataset.says = '0';
      who.appendChild(el('span', 'foldsum'));
      var gist = el('div', 'gist', gistOf(line.text));
      gist.setAttribute('dir', 'auto');
      turn.appendChild(gist);
      (function (g) {
        turn.addEventListener('click', function (e) {
          if (!foldOn) { return; }
          // An open request's own text stays selectable and its links/chips
          // stay clickable: there only the header line folds it back.
          if (turn.classList.contains('open') && !e.target.closest('.who')) { return; }
          var sel = window.getSelection && window.getSelection();
          if (sel && String(sel).length) { return; }
          toggleGroup(g);
        });
      })(bk);
    } else {
      foldMember(turn, false);
    }
    var body = el('div', 'body md');
    body.appendChild(md(line.text, line.paths));
    turn.appendChild(body);
    log.appendChild(turn);
  });
  applyFold();

  var newAsk = false;
  if (chat.ask && chat.ask.parts && chat.ask.parts.length) {
    var ac = askCard(chat.ask, false);
    log.appendChild(ac);
    /* Reported 3.10: the card was there, below where the reader had scrolled,
       and it looked missing. Reported 8.10: being pulled down to it while
       reading was a jump. Now: at the bottom you see it; higher up, a pill
       says a question is waiting, and one click brings it. */
    var askSig = chat.sid + '|' + (chat.ask.parts[0].question || '');
    ac.dataset.k = 'ask|' + askSig;
    newAsk = askSig !== lastAskSeen;
    lastAskSeen = askSig;
  }

  autoOpenImages();
  if (wasDown) { stickBottom = true; }
  if (stickBottom) {
    toBottom();
    hidePill();
  } else {
    // Reported 8.10: the reader's line stays where the eye was, whatever the
    // rebuild added above (earlier turns) or dropped (the sliding window).
    if (!restoreAnchor()) {
      if (grewUp) { scroll.scrollTop = scroll.scrollHeight - fromBottom; }
    }
    // Something new arrived below while reading higher up: say so, don't move.
    // (A question new to this screen is announced the same way — 3.10 report.)
    if (newAsk) {
      showPill('\(Lang.t("שאלה ממתינה למטה ↓", "A question is waiting below ↓"))');
    } else if (sameChat && lastTailSig && tailSig !== lastTailSig && !grewUp) {
      showPill('\(Lang.t("הודעות חדשות ↓", "New messages ↓"))');
    }
  }
  grewUp = false;
  lastTailSig = tailSig;
}

/* ‏**להראות מוקדם יותר.** החלון גדל בצד שיחה, והדף מבקש ציור מחדש.
   ⛔ שיחה ארוכה נפתחה באמצע ולא הייתה שום דרך להגיע לראשה — נמדד 28.8. */
var grewUp = false;
var askingEarlier = false;

function askEarlier() {
  if (askingEarlier) { return; }
  askingEarlier = true;
  grewUp = true;
  stickBottom = false;
  var bar = document.getElementById('earlier');
  if (bar) { bar.textContent = ''; bar.appendChild(el('span', null, 'טוען…')); }
  send('more');
  setTimeout(function () { askingEarlier = false; }, 1200);
}

/* ================= Collapsed view =================
   Requested 21.10: scroll along your own requests through a long
   conversation. In collapsed mode each of the user's messages is a header (one
   or two lines, ellipsis), and the answer under it — replies and tool lines
   up to the next message — is folded; a click expands it and folds it back.
   - The choice is remembered across launches (localStorage, like outsOpen).
   - Which requests are open is remembered per conversation by block key, so
     the 1.5 s rebuilds keep them open.
   - The log stays a flat list of blocks; only classes change (see the CSS
     note), so the reading-position anchor and search marks keep working. */
var foldOn = false;
try { foldOn = localStorage.getItem('chatFold') === '1'; } catch (e) {}
var foldOpen = {};
var lastAtStart = true;

/* One header line out of a message: markdown marks dropped, white space
   folded. The CSS clamps it to two lines. */
function gistOf(text) {
  var s = String(text || '').replace(/```/g, ' ').replace(/[`*#>]/g, '')
    .replace(/\\s+/g, ' ').trim();
  return s.length > 600 ? s.slice(0, 600) : s;
}

function foldBlocks() {
  return Array.prototype.slice.call(document.getElementById('log').children)
    .filter(function (k) { return k.dataset && k.dataset.g; });
}

function headOf(g) {
  var all = foldBlocks();
  for (var i = 0; i < all.length; i++) { if (all[i].dataset.k === g) { return all[i]; } }
  return null;
}

function foldSummary(head, open) {
  var acts = Number(head.dataset.acts || 0), says = 0;
  // Count what really follows (the head's own counters are filled while the
  // log is built, but a pending turn may have no answer yet).
  foldBlocks().forEach(function (b) {
    if (b.dataset.g !== head.dataset.g || b === head) { return; }
    if (b.classList.contains('turn')) { says++; }
  });
  var parts = [];
  if (says) { parts.push(says + ' ' + (says === 1 ? '\(Lang.t("תשובה", "reply"))' : '\(Lang.t("תשובות", "replies"))')); }
  if (acts) { parts.push(acts + ' ' + (acts === 1 ? '\(Lang.t("פעולה", "action"))' : '\(Lang.t("פעולות", "actions"))')); }
  if (!parts.length) { return '\(Lang.t("עוד אין תשובה", "no answer yet"))'; }
  return (open ? '▾ ' : '▸ ') + parts.join(' · ');
}

function applyFold() {
  var log = document.getElementById('log');
  var btn = document.getElementById('foldbtn');
  if (btn) { btn.className = 'btn' + (foldOn ? ' on' : ''); }
  if (foldOn) { log.classList.add('fold'); } else { log.classList.remove('fold'); }
  foldBlocks().forEach(function (b) {
    var g = b.dataset.g;
    var open = !!foldOpen[g];
    if (b.dataset.k === g) {
      if (open) { b.classList.add('open'); } else { b.classList.remove('open'); }
      var sum = b.querySelector('.foldsum');
      if (sum) { sum.textContent = foldSummary(b, open); }
    } else if (open) {
      b.classList.remove('fo');
    } else {
      b.classList.add('fo');
    }
  });
}

/* Expand or fold one request's answer, keeping its header where the eye is. */
function toggleGroup(g) {
  var box = document.getElementById('logscroll');
  var head = headOf(g);
  var before = head ? head.getBoundingClientRect().top : 0;
  if (foldOpen[g]) { delete foldOpen[g]; } else { foldOpen[g] = true; }
  applyFold();
  if (head) {
    var delta = head.getBoundingClientRect().top - before;
    if (delta) { box.scrollTop = box.scrollTop + delta; placedTop = box.scrollTop; }
  }
  stickBottom = nearBottom();
  if (stickBottom) { hidePill(); }
  captureAnchor();
}

/* A search match inside a folded answer: open that answer first. */
function revealFolded(node) {
  if (!foldOn) { return; }
  var log = document.getElementById('log');
  var b = node;
  while (b && b.parentNode !== log) { b = b.parentNode; }
  if (!b || !b.dataset || !b.dataset.g || foldOpen[b.dataset.g]) { return; }
  foldOpen[b.dataset.g] = true;
  applyFold();
}

function toggleFold() {
  var box = document.getElementById('logscroll');
  var top = box.getBoundingClientRect().top;
  // The request being read stays in view: its header goes to the top edge.
  var keep = null;
  if (!stickBottom) {
    var all = foldBlocks();
    for (var i = 0; i < all.length; i++) {
      var r = all[i].getBoundingClientRect();
      if (r.height && r.bottom > top) { keep = all[i].dataset.g; break; }
    }
  }
  foldOn = !foldOn;
  try { localStorage.setItem('chatFold', foldOn ? '1' : '0'); } catch (e) {}
  applyFold();
  var head = keep ? headOf(keep) : null;
  if (stickBottom || !head) {
    toBottom();
    stickBottom = true;
  } else {
    box.scrollTop = box.scrollTop + (head.getBoundingClientRect().top - top) - 8;
    placedTop = box.scrollTop;
  }
  captureAnchor();
  // Collapsed, the default window holds only a dozen requests: load more once.
  if (foldOn && !lastAtStart && document.querySelectorAll('#log .turn.you').length < 15) {
    send('more');
  }
}

document.getElementById('foldbtn').addEventListener('click', toggleFold);

/* ‏**מי עובד ברגע זה, בתוך השיחה.** כמו בקלוד־קוד עצמו: שורה לכל סוכן —
   הסוג, המשימה, מה הוא עושה עכשיו, כמה זמן, וכמה הקשר צבר.

   ⛔ הרצועה חיה מחוץ ליומן בכוונה. סוכן אינו דבר ש**נאמר** אלא מצב שקורה,
      ושורה בתוך היומן הייתה נגללת למעלה ונעלמת בדיוק כשהיא רלוונטית. */
var CREW_SHOWN = 4;

function paintCrewStrip(crew) {
  var strip = document.getElementById('crewstrip');
  strip.textContent = '';
  if (!crew.length) { strip.className = ''; return; }
  strip.className = 'on';

  crew.slice(0, CREW_SHOWN).forEach(function (a) {
    var row = el('div', 'crewline');
    var beat = el('span', 'beat');
    beat.appendChild(spinner(11));
    row.appendChild(beat);
    row.appendChild(el('span', 'kind', a.kind));
    row.appendChild(el('span', 'what', a.task));
    row.appendChild(el('span', 'now', a.doing || a.say || ''));
    row.appendChild(el('span', 'lap', a.since));
    row.appendChild(el('span', 'ctx', a.context));
    row.addEventListener('click', function () { send('agents'); });
    strip.appendChild(row);
  });

  if (crew.length > CREW_SHOWN) {
    var more = el('div', null, '\(Lang.t("ועוד ", "and "))' + (crew.length - CREW_SHOWN) + '\(Lang.t(" סוכנים — לחיצה פותחת את הרשימה", " agents — click to open the list"))');
    more.id = 'crewmore';
    more.addEventListener('click', function () { send('agents'); });
    strip.appendChild(more);
  }
}

/* ================= מסמך ================= */

var docEditEl = document.getElementById('docedit');
var docShown = '';
var docPathNow = '';
var docDirty = false;
var closeArmed = false;
var cm = null;   // the CodeMirror editor while a file is being edited
function edValue() { return cm ? cm.value : docEditEl.value; }
function edOpen() { return !!cm || docEditEl.className === 'on'; }
var UNSAVED = '\(Lang.t("● לא נשמר", "● unsaved"))';

/* ================= the Markdown editor =================
   Every change goes through execCommand('insertText'), never through
   .value, so the browser's own undo and redo keep working. */
function edOnInput() {
  if (docDirty) { return; }
  docDirty = true;
  var note = document.getElementById('docnote');
  note.textContent = UNSAVED; note.className = 'warn';
}

/* Undo history lives on the element, and setting .value does not clear it:
   ⌘Z after opening a second file replayed edits from the first one
   (measured 30.10). Each opened file gets a fresh textarea. */
function freshEditor() {
  var n = docEditEl.cloneNode(false);
  docEditEl.parentNode.replaceChild(n, docEditEl);
  docEditEl = n;
  n.addEventListener('input', edOnInput);
  n.addEventListener('keydown', edOnKey);
  return n;
}

function edInsert(text) { document.execCommand('insertText', false, text); }

function edLineStart(v, at) { var k = v.lastIndexOf(NL, at - 1); return k + 1; }

/* "  - [ ] ", "1. ", "> " at the start of a line: what Enter repeats. */
function edMarker(line) {
  var k = 0;
  while (k < line.length && line.charAt(k) === ' ') { k++; }
  var ind = line.slice(0, k), rest = line.slice(k);
  var heads = ['- [ ] ', '- [x] ', '- [X] ', '* [ ] ', '- ', '* ', '+ ', '> '];
  for (var h = 0; h < heads.length; h++) {
    if (rest.slice(0, heads[h].length) === heads[h]) {
      var next = heads[h].indexOf('[') >= 0 ? heads[h].charAt(0) + ' [ ] ' : heads[h];
      return { all: ind + heads[h], next: ind + next };
    }
  }
  var d = 0;
  while (d < rest.length && d < 9 && rest.charAt(d) >= '0' && rest.charAt(d) <= '9') { d++; }
  if (d > 0 && (rest.charAt(d) === '.' || rest.charAt(d) === ')') && rest.charAt(d + 1) === ' ') {
    return { all: ind + rest.slice(0, d + 2), next: ind + (Number(rest.slice(0, d)) + 1) + rest.charAt(d) + ' ' };
  }
  return null;
}

function edWrap(mark) {
  var a = docEditEl.selectionStart, b = docEditEl.selectionEnd;
  var sel = docEditEl.value.slice(a, b);
  edInsert(mark + sel + mark);
  if (!sel) { docEditEl.setSelectionRange(a + mark.length, a + mark.length); }
}

/* Tab and Shift-Tab indent or outdent every line the selection touches. */
function edIndent(out) {
  var v = docEditEl.value, a = docEditEl.selectionStart, b = docEditEl.selectionEnd;
  var start = edLineStart(v, a);
  var end = v.indexOf(NL, b > a ? b - 1 : b); if (end < 0) { end = v.length; }
  var lines = v.slice(start, end).split(NL);
  var moved = lines.map(function (l) {
    if (!out) { return '  ' + l; }
    return l.slice(0, 2) === '  ' ? l.slice(2) : (l.charAt(0) === ' ' ? l.slice(1) : l);
  });
  var text = moved.join(NL);
  if (text === lines.join(NL)) { return; }
  docEditEl.setSelectionRange(start, end);
  edInsert(text);
  var first = moved[0].length - lines[0].length;
  docEditEl.setSelectionRange(Math.max(start, a + first), start + text.length - (end - b));
}

function edOnKey(e) {
  if (e.isComposing) { return; }
  var mod = e.metaKey || e.ctrlKey;
  if (mod && !e.shiftKey && (e.key === 'b' || e.key === 'i')) {
    e.preventDefault(); edWrap(e.key === 'b' ? '**' : '*'); return;
  }
  if (e.key === 'Tab' && !mod) { e.preventDefault(); edIndent(e.shiftKey); return; }
  if (e.key !== 'Enter' || mod || e.shiftKey || e.altKey) { return; }
  var v = docEditEl.value, at = docEditEl.selectionStart;
  if (at !== docEditEl.selectionEnd) { return; }
  var start = edLineStart(v, at);
  var m = edMarker(v.slice(start, at));
  if (!m) { return; }
  e.preventDefault();
  if (v.slice(start, at) === m.all) {
    // Enter on an empty item ends the list, as every editor does
    docEditEl.setSelectionRange(start, at);
    document.execCommand('delete');
    return;
  }
  edInsert(NL + m.next);
}
docEditEl.addEventListener('input', edOnInput);
docEditEl.addEventListener('keydown', edOnKey);

/* Closing with unsaved changes asks once: the second click closes. */
function closeDocAsked() {
  if (edOpen() && docDirty && !closeArmed) {
    closeArmed = true;
    var note = document.getElementById('docnote');
    note.textContent = '\(Lang.t("יש שינויים שלא נשמרו — לחיצה נוספת סוגרת בלי לשמור", "Unsaved changes — click again to close without saving"))';
    note.className = 'warn';
    setTimeout(function () { closeArmed = false; }, 5000);
    return true;
  }
  docDirty = false;
  send('closeDoc');
  return true;
}

function paintDoc(doc) {
  var pane = document.getElementById('docpane');
  var cmHost = document.getElementById('doccm');
  if (!doc || !doc.editing) {
    if (cm) { cm.destroy(); cm = null; }
    cmHost.className = '';
  }
  if (!doc) { pane.className = ''; docShown = ''; return; }
  pane.className = 'on';
  docPathNow = doc.path;

  document.getElementById('docname').textContent = doc.name;
  var note = document.getElementById('docnote');
  note.textContent = doc.note || '';
  note.className = doc.warn ? 'warn' : '';
  if (doc.editing && docDirty && docShown === doc.stamp) { note.textContent = UNSAVED; note.className = 'warn'; }
  document.getElementById('docmode').textContent = doc.editing ? '\(Lang.t("שמירה", "Save"))' : '\(Lang.t("עריכה", "Edit"))';

  var scroll = document.getElementById('docscroll');
  var view = document.getElementById('docview');

  if (doc.editing) {
    scroll.className = 'scroll editing';
    view.style.display = 'none';
    if (window.PeachEditor) {
      docEditEl.className = '';
      cmHost.className = 'on';
      if (docShown !== doc.stamp || !cm) {
        if (cm) { cm.destroy(); }
        cm = window.PeachEditor.create(cmHost, doc.text, edOnInput, { markdown: /[.](md|markdown)$/i.test(doc.path) });
        docShown = doc.stamp; docDirty = false; closeArmed = false;
        cm.focus();
      }
      return;
    }
    docEditEl.className = 'on';
    // בזמן הקלדה אין לדרוס את מה שנכתב — רק בפתיחה או בהחלפת קובץ
    if (docShown !== doc.stamp) {
      freshEditor().className = 'on';
      docEditEl.value = doc.text; docShown = doc.stamp; docDirty = false; closeArmed = false;
    }
    return;
  }

  scroll.className = 'scroll';
  docEditEl.className = '';
  view.style.display = '';
  if (docShown !== doc.stamp) {
    view.textContent = '';
    cardsEnabled = false;
    mdBase = doc.path.slice(0, doc.path.lastIndexOf('/'));
    var whole = md(doc.text, doc.paths);
    mdBase = '';
    cardsEnabled = true;
    docShown = doc.stamp;
    /* A long file is laid out in slices: the first screenful at once, the
       rest after the first paint. 2,677 lines took ~470 ms before anything
       showed (measured 30.10). */
    var stamp = doc.stamp;
    function slice(n) {
      for (var k = 0; k < n && whole.firstChild; k++) { view.appendChild(whole.firstChild); }
      if (whole.firstChild) {
        setTimeout(function () { if (docShown === stamp) { slice(400); } }, 0);
      } else { view.dataset.done = stamp; }
    }
    slice(80);
  }
}

/* ================= לוח־הפקודות ================= */

var COMMANDS = [];
var paletteEl = document.getElementById('palette');
var fieldEl = document.getElementById('field');
var shown = [];
var picked = 0;

function setCommands(list) { COMMANDS = list || []; }

/* נקרא מהתפריט — ממקד את השדה ופותח את הלוח, בלי להקליד לוכסן ביד */
function startCommand() {
  fieldEl.focus();
  if (fieldEl.value.charAt(0) !== '/') { fieldEl.value = '/' + fieldEl.value; }
  refreshPalette();
}

/* הלוח נפתח רק כשהשורה כולה היא פקודה שעדיין נכתבת: לוכסן בתחילתה,
   ובלי רווח אחריו. לוכסן בתוך נתיב אינו פקודה. */
function paletteQuery() {
  var value = fieldEl.value;
  if (value.charAt(0) !== '/') { return null; }
  if (value.indexOf(' ') >= 0 || value.indexOf(NL) >= 0) { return null; }
  return value.slice(1);
}

function score(cmd, q) {
  var name = cmd.name.toLowerCase();
  if (!q) { return 2; }
  if (name.indexOf(q) === 0) { return 0; }
  if (name.indexOf(q) > 0) { return 1; }
  if (cmd.hint.indexOf(q) >= 0) { return 3; }
  return -1;
}

function refreshPalette() {
  var q = paletteQuery();
  if (q === null) { closePalette(); return; }
  var needle = q.toLowerCase();
  shown = COMMANDS
    .map(function (c) { return { c: c, s: score(c, needle) }; })
    .filter(function (x) { return x.s >= 0; })
    .sort(function (a, b) { return a.s - b.s; })
    .slice(0, 9)
    .map(function (x) { return x.c; });

  if (!shown.length) { closePalette(); return; }
  if (picked >= shown.length) { picked = 0; }

  paletteEl.textContent = '';
  shown.forEach(function (c, i) {
    var row = el('div', 'cmd' + (i === picked ? ' pick' : ''));
    row.appendChild(el('span', 'nm', '/' + c.name));
    row.appendChild(el('span', 'kd', c.kind));
    row.appendChild(el('span', 'hn', c.hint));
    if (c.interactive) { row.appendChild(el('span', 'pk', '\(Lang.t("התשובה במסוף", "Answer in the terminal"))')); }
    row.addEventListener('mousedown', function (e) {
      e.preventDefault();
      picked = i;
      complete();
    });
    paletteEl.appendChild(row);
  });
  paletteEl.className = 'on';
}

function closePalette() {
  paletteEl.className = '';
  paletteEl.textContent = '';
  shown = [];
  picked = 0;
}

function complete() {
  if (!shown.length) { return; }
  fieldEl.value = '/' + shown[picked].name + ' ';
  closePalette();
  fieldEl.focus();
}

/* ================= הדבקה וגרירה ================= */

/* מה שהודבק או נגרר. הפריט אינו נשלח כתמונה — הוא נכתב לדיסק, ומה
   שנכנס לשורה הוא **הנתיב**. כך המסוף קורא אותו בעצמו, בדיוק כמו
   שהיה קורא קובץ שכתבת את שמו ביד. */
var clipped = [];
var clipEl = document.getElementById('clip');
var dropEl = document.getElementById('drop');
var dragDepth = 0;

/* בלי ביטוי רגולרי: הדף חי בתוך מחרוזת של סוויפט, ולוכסן אחורי בו
   עובר שתי שכבות פענוח — מקור לכמה תקלות בעבר. */
function rtrim(text) {
  var out = String(text);
  while (out.length && ' \t'.indexOf(out.charAt(out.length - 1)) >= 0) {
    out = out.slice(0, -1);
  }
  return out;
}

function drawClips() {
  clipEl.textContent = '';
  clipEl.className = clipped.length ? 'on' : '';
  clipped.forEach(function (path, i) {
    var chip = el('div', 'clipped');
    chip.title = '\(Lang.t("לחיצה פותחת · × מסירה", "Click opens · × removes"))';

    // תצוגה מקדימה בתג עצמו. בלעדיה הצירוף הוא שורת־טקסט ארוכה שאי־אפשר
    // לדעת מה יש בה עד ששולחים — וזו בדיוק התלונה.
    var have = assets[path];
    if (have && have.src) {
      var thumb = document.createElement('img');
      thumb.src = have.src;
      thumb.alt = '';
      chip.appendChild(thumb);
    } else if (isImage(path) && !have) {
      send('asset', { path: path });
    }

    chip.appendChild(el('span', null, baseName(path)));
    chip.addEventListener('click', function (e) {
      if (e.target.tagName === 'U') { return; }
      send('reveal', { path: path });
    });
    var kill = el('u', null, '×');
    kill.title = '\(Lang.t("להסיר", "Remove"))';
    kill.addEventListener('click', function (e) {
      e.stopPropagation();
      var at = fieldEl.value.indexOf(path);
      if (at >= 0) {
        fieldEl.value = (fieldEl.value.slice(0, at) +
                         fieldEl.value.slice(at + path.length)).replace('  ', ' ').trim();
      }
      clipped.splice(i, 1);
      drawClips();
    });
    chip.appendChild(kill);
    clipEl.appendChild(chip);
  });
}

/* נקרא מהצד השני אחרי שהקובץ נכתב */
function attached(path) {
  if (!path) { return; }
  clipped.push(path);
  var value = fieldEl.value;
  fieldEl.value = (value ? rtrim(value) + ' ' : '') + path + ' ';
  fieldEl.focus();
  fieldEl.selectionStart = fieldEl.selectionEnd = fieldEl.value.length;
  drawClips();
}

function stash(file) {
  if (!file) { return; }
  var reader = new FileReader();
  reader.onload = function () {
    var raw = String(reader.result);
    var comma = raw.indexOf(',');
    if (comma < 0) { return; }
    send('stash', { data: raw.slice(comma + 1), name: file.name || '\(Lang.t("הדבקה.png", "pasted.png"))' });
  };
  reader.readAsDataURL(file);
}

document.addEventListener('paste', function (e) {
  var items = (e.clipboardData && e.clipboardData.items) || [];
  var took = false;
  for (var i = 0; i < items.length; i++) {
    if (items[i].kind !== 'file') { continue; }
    var file = items[i].getAsFile();
    if (!file) { continue; }
    stash(file);
    took = true;
  }
  if (took) { e.preventDefault(); }
});

/* dragenter/dragleave נורים גם על אלמנטים פנימיים — מונה עומק מונע
   הבהוב של שכבת־השחרור בכל מעבר מעל ילד */
document.addEventListener('dragenter', function (e) {
  e.preventDefault();
  dragDepth++;
  dropEl.className = 'on';
});
document.addEventListener('dragover', function (e) { e.preventDefault(); });
document.addEventListener('dragleave', function (e) {
  e.preventDefault();
  dragDepth = Math.max(0, dragDepth - 1);
  if (!dragDepth) { dropEl.className = ''; }
});
document.addEventListener('drop', function (e) {
  e.preventDefault();
  dragDepth = 0;
  dropEl.className = '';
  var files = (e.dataTransfer && e.dataTransfer.files) || [];
  for (var i = 0; i < files.length; i++) { stash(files[i]); }
});

/* גלילה להודעה האחרונה שהמשתמש כתב */
/* לחיצה חוזרת מטיילת אחורה בהודעות שלך: האחרונה, זו שלפניה, וכן הלאה.
   בלי זה, כשההודעה האחרונה ממילא על המסך — נראה שהכפתור אינו עושה דבר. */
var mineAt = -1;
var mineWhen = 0;

function toMine() {
  var mine = document.querySelectorAll('#log .turn.you');
  if (!mine.length) { return; }

  var now = Date.now();
  if (now - mineWhen > 4000) { mineAt = -1; }
  mineWhen = now;

  mineAt += 1;
  if (mineAt >= mine.length) { mineAt = 0; }

  var target = mine[mine.length - 1 - mineAt];
  stickBottom = false;
  target.scrollIntoView({ block: 'center' });

  // הבזק קצר, כדי שיהיה ברור לאן קפצנו
  // classList, not className: the collapsed view's .open must survive the flash.
  target.classList.add('flash');
  setTimeout(function () { target.classList.remove('flash'); }, 900);
}

/* ================= צריכה ================= */
/* מה נשרף, ומה זה שווה. הבסיס הוא מחירון־הרשימה למיליון טוקנים, ולכן
   המספר הוא **שווי־עבודה** ולא חיוב בכרטיס — מנוי אינו מתומחר כך. */

var spanKey = 'today';
var lastSpend = null;

/* ⛔ ‏**אין כאן דולרים.** המשתמש במנוי, ומחיר־רשימה אינו מה שהוא משלם —
   מספר כזה נראה מדיד והוא בדיוני. מה שמוצג הוא חלק־מהחלון וטוקנים. */
function share(v) {
  if (!v) { return '0%'; }
  if (v >= 0.1) { return Math.round(v * 100) + '%'; }
  if (v < 0.005) { return '<1%'; }
  return (v * 100).toFixed(1) + '%';
}

function toks(n) {
  n = n || 0;
  if (n >= 1000000000) { return (n / 1000000000).toFixed(1) + 'B'; }
  if (n >= 1000000) { return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1) + 'M'; }
  if (n >= 1000) { return Math.round(n / 1000) + 'k'; }
  return String(n);
}

/* צבע לכל דגם, כדי שרצועת־הפילוח תיקרא בלי מקרא */
var MODEL_TINT = { '\(Lang.t("פייבל", "Fable"))': '#f2a365', '\(Lang.t("אופוס", "Opus"))': '#d98b4a', '\(Lang.t("מיתוס", "Mythos"))': '#c97a55',
                   '\(Lang.t("סונט", "Sonnet"))': '#6f8fa8', '\(Lang.t("הייקו", "Haiku"))': '#63d18c' };
function tint(name) { return MODEL_TINT[name] || '#5f6a63'; }

function bigStat(value, label, side) {
  var box = el('div', 'big' + (side ? ' side' : ''));
  box.appendChild(el('span', 'v', value));
  box.appendChild(el('span', 'l', label));
  return box;
}

/* ‏**המכסה — בצורה שקלוד מציג אותה.** אחוז מהתקרה, ומתי היא נאפסת.
   ⛔ המספר הזה אינו נגזר מהיומנים: רק השרת יודע מה התקרה. הוא מגיע מדוגם
      שרץ ברקע וכותב לדיסק, ולכן הוא נושא גיל — ודגימה ישנה אומרת זאת. */
function paintQuota(q, burn) {
  var host = document.getElementById('quota');
  host.textContent = '';
  if (!q) { return; }

  (q.rows || []).forEach(function (r) {
    var row = el('div', 'qrow ' + (r.severity || 'normal') + (r.active ? ' live' : ''));
    row.appendChild(el('span', 'ql', r.label));
    var track = el('div', 'qtrack');
    var fill = el('div', 'qfill');
    fill.style.width = Math.max(0, Math.min(100, r.percent)) + '%';
    track.appendChild(fill);
    row.appendChild(track);
    row.appendChild(el('span', 'qp', r.percent + '%'));
    // בחלון־חמש־השעות אפשר גם לומר מה נשרף בו בפועל, ולא רק כמה אחוז
    var inWindow = (r.label.indexOf('\(Lang.t("חמש שעות", "five hours"))') >= 0 && burn && burn.output > 0)
                 ? toks(burn.output) : '';
    row.appendChild(el('span', 'qb', inWindow));
    row.appendChild(el('span', 'qw', r.at ? ('\(Lang.t("נאפס ", "resets "))' + r.at + ' · ' + r.until) : ''));
    host.appendChild(row);
  });

  var note = el('div', null, '');
  note.id = 'quotanote';
  if (q.error) { note.className = 'warn'; note.textContent = '\(Lang.t("המכסה לא נקראה — ", "Quota was not read — "))' + q.error; }
  else if (q.missing) {
    note.className = 'warn';
    note.textContent = '\(Lang.t("המכסה אינה נדגמת. להתקנה: tools/install-quota-poll.sh", "Quota is not being sampled. To install: tools/install-quota-poll.sh"))';
  } else if (q.stale) {
    note.className = 'warn';
    note.textContent = '\(Lang.t("הדגימה בת ", "sample is "))' + Math.round(q.age / 60) + '\(Lang.t(" דקות — ייתכן שהמספר כבר אינו נכון", "m — the number may already be stale"))';
  } else if (!(q.rows || []).length) {
    note.textContent = '\(Lang.t("אין מגבלות מדווחות", "No limits reported"))';
  } else {
    note.textContent = '\(Lang.t("נדגם לפני ", "sampled "))' + (q.age < 60 ? '\(Lang.t("פחות מדקה", "under a minute"))' : (Math.round(q.age / 60) + '\(Lang.t(" דקות", "m"))'));
  }
  host.appendChild(note);
}

function paintSpend(data) {
  lastSpend = data;
  paintQuota(data.quota, data.windowNow);
  var pills = { today: 'spanday', week: 'spanweek', all: 'spanall' };
  Object.keys(pills).forEach(function (k) {
    document.getElementById(pills[k]).className = 'pill' + (k === spanKey ? ' on' : '');
  });

  var state = document.getElementById('spendstate');
  state.textContent = '';
  if (data.building > 0) {
    state.appendChild(spinner(15));
    state.appendChild(el('span', null, '\(Lang.t(" סופר · ", " counting · "))' + data.building + '\(Lang.t(" יומנים", " logs"))'));
  } else {
    state.appendChild(el('span', null, data.logs + '\(Lang.t(" יומנים נספרו", " logs counted"))'));
  }

  var win = data[spanKey] || { cost: 0, sessions: [], models: [] };
  var head = document.getElementById('spendhead');
  head.textContent = '';
  head.appendChild(bigStat(toks(win.output), '\(Lang.t("טוקני־פלט", "output tokens"))'));
  head.appendChild(bigStat(toks(win.read), '\(Lang.t("מהמטמון", "from cache"))', true));
  head.appendChild(bigStat(toks(win.write), '\(Lang.t("למטמון", "to cache"))', true));
  head.appendChild(bigStat(toks(win.input), '\(Lang.t("קלט חדש", "new input"))', true));
  head.appendChild(bigStat(String(win.calls || 0), '\(Lang.t("קריאות", "reads"))', true));
  head.appendChild(el('div', 'spacer'));

  // ארבעה־עשר ימים אחורה. הגובה יחסי לגבוה ביותר — סרגל מוחלט לא היה אומר דבר.
  var bars = data.bars || [];
  var top = 0;
  bars.forEach(function (b) { if (b.weight > top) { top = b.weight; } });
  var strip = el('div');
  strip.id = 'bars';
  bars.forEach(function (b) {
    var col = el('div', 'bar' + (b.today ? ' now' : ''));
    var fill = el('i');
    fill.style.height = Math.max(2, Math.round((top ? b.weight / top : 0) * 40)) + 'px';
    fill.title = b.day + ' · ' + toks(b.output) + '\(Lang.t(" פלט", " output"))';
    col.appendChild(fill);
    col.appendChild(el('b', null, b.day));
    strip.appendChild(col);
  });
  head.appendChild(strip);

  var host = document.getElementById('spendlist');
  host.textContent = '';
  if (!win.sessions.length) {
    var none = el('div', null, data.ready ? '\(Lang.t("אין צריכה בחלון הזה.", "No usage in this window."))' : '\(Lang.t("עוד סופר…", "still counting…"))');
    none.id = 'spendnote';
    host.appendChild(none);
    return;
  }

  // רצועת־פילוח לפי דגם
  var strap = el('div', 'spendbar');
  (win.models || []).forEach(function (m) {
    var seg = el('span');
    seg.style.flex = String(Math.max(m.share, 0.005));
    seg.style.background = tint(m.name);
    seg.title = m.name + ' · ' + share(m.share);
    strap.appendChild(seg);
  });
  host.appendChild(strap);

  var line = el('div', 'spendhr');
  (win.models || []).forEach(function (m) {
    var tag = el('span', null, m.name + ' ' + share(m.share));
    tag.style.color = tint(m.name);
    line.appendChild(tag);
  });
  line.appendChild(el('hr'));
  host.appendChild(line);

  var title = el('div', 'spendhr');
  title.appendChild(el('span', null, '\(Lang.t("לפי שיחה", "by conversation"))'));
  title.appendChild(el('hr'));
  host.appendChild(title);

  win.sessions.forEach(function (r) {
    var row = el('div', 'spendrow' + (r.open ? ' live' : ''));
    row.appendChild(el('span', 'money', share(r.share)));
    var nm = el('span', 'nm', r.title || r.project || '\(Lang.t("שיחה", "conversation"))');
    row.appendChild(nm);
    row.appendChild(el('span', 'md', r.model));
    row.appendChild(el('span', 'tok', toks(r.out) + '\(Lang.t(" פלט", " output"))'));
    row.appendChild(el('span', 'cl', r.calls + '\(Lang.t(" קריאות", " reads"))'));
    if (r.open) {
      row.addEventListener('click', function () { send('open', { sid: r.sid }); });
    }
    host.appendChild(row);
  });
}

/* ================= שער ================= */

/* ⛔ An exception inside paint left the screen half-drawn and silent —
   reported 3.10: conversation 020 stopped at yesterday's lines, and "take
   down" did nothing. Every page error now reaches a log file. */
window.addEventListener('error', function (e) {
  try { send('pageError', { text: String(e.message) + ' @' + e.lineno + ':' + e.colno + ' ' + (e.error && e.error.stack || '') }); } catch (x) {}
});

function paint(data) {
  try { paintInner(data); }
  catch (e) {
    try { send('pageError', { text: 'paint: ' + e.message + ' ' + (e.stack || '') }); } catch (x) {}
  }
}

function paintInner(data) {
  var search = data.search;
  var chat = data.chat;
  var crew = data.crew;
  var book = data.book;
  var works = data.works;
  var asks = data.asks;
  /* סדר הקדימות בין המסכים, מהעליון לתחתון */
  var mode = 'rack';
  if (data.reader && data.doc) { mode = 'reader'; }
  else if (data.spend) { mode = 'spend'; }
  else if (asks) { mode = 'asks'; }
  else if (works) { mode = 'works'; }
  else if (book) { mode = 'book'; }
  else if (crew) { mode = 'crew'; }
  else if (search) { mode = 'search'; }
  else if (chat) { mode = 'chat'; }

  /* ⇒ נמשכת בכל פעימה, לא רק כשהמסך מתחלף: שאלה שנפתחה תוך כדי קריאה
     חייבת להופיע מיד, וזה כל מה שהבאג הזה היה. */
  paintAlerts(mode === 'chat' ? (data.alerts || []) : []);

  /* The reader is the chat view's document pane, alone and full-width. */
  var chatOn = mode === 'chat' || mode === 'reader';

  document.getElementById('rackview').className = 'view' + (mode === 'rack' ? ' on' : '');
  document.getElementById('chatview').className = 'view' + (chatOn ? ' on' : '') + (mode === 'reader' ? ' reader' : '');
  document.getElementById('searchview').className = 'view' + (mode === 'search' ? ' on' : '');
  document.getElementById('crewview').className = 'view' + (mode === 'crew' ? ' on' : '');
  document.getElementById('bookview').className = 'view' + (mode === 'book' ? ' on' : '');
  document.getElementById('worksview').className = 'view' + (mode === 'works' ? ' on' : '');
  document.getElementById('asksview').className = 'view' + (mode === 'asks' ? ' on' : '');
  document.getElementById('spendview').className = 'view' + (mode === 'spend' ? ' on' : '');

  if (mode === 'spend') {
    paintSpend(data.spend);
  } else if (mode === 'asks') {
    paintAsks(asks, data.live || []);
  } else if (mode === 'works') {
    paintWorks(works);
  } else if (mode === 'book') {
    paintBook(book);
  } else if (mode === 'crew') {
    paintCrew(crew);
    setPace(crew.filter(function (a) { return a.state === 'run'; }).length);
  } else if (mode === 'search') {
    if (document.activeElement !== findEl && findEl.value !== search.query) {
      findEl.value = search.query;
    }
    paintSearch(search);
    if (document.activeElement !== findEl) { findEl.focus(); }
  } else if (mode === 'reader') {
    paintDoc(data.doc);
  } else if (mode === 'chat') {
    paintChat(chat);
    paintDoc(data.doc);
    syncFind(data.find || null, chat);
  } else {
    lastKey = '';
    paintRack(data);
  }
  if (mode !== 'rack' && dialBuf) { dialClear(); }
}

/* ================= מקשים ופעולות ================= */

fieldEl.addEventListener('input', refreshPalette);

/* ================= ההודעה הבאה — ghost text =================
   Peach predicts what you would type next (Suggest.swift) and shows it in
   the empty field. Tab, right-arrow or a click on the hint takes it into
   the field; Enter then sends it like anything you typed. Nothing is sent
   on its own. */
var ghostText = '';
var basePlaceholder = fieldEl.placeholder;
var gtakeEl = document.getElementById('gtake');
function paintGhost(text) {
  if (text === ghostText) { return; }
  ghostText = text;
  fieldEl.placeholder = text ? text + '   ⇥' : basePlaceholder;
  fieldEl.className = text ? 'ghost' : '';
  gtakeEl.textContent = text ? '\(Lang.t("טאב — לקחת את ההצעה ·", "Tab — take the suggestion ·"))' : '';
  gtakeEl.className = text ? 'on' : '';
}
function takeGhost() {
  if (!ghostText || fieldEl.value) { return false; }
  fieldEl.value = ghostText;
  fieldEl.focus();
  gtakeEl.className = '';
  fieldEl.selectionStart = fieldEl.selectionEnd = fieldEl.value.length;
  return true;
}
gtakeEl.addEventListener('click', function () { takeGhost(); });
fieldEl.addEventListener('input', function () {
  gtakeEl.className = ghostText && !fieldEl.value ? 'on' : '';
});

fieldEl.addEventListener('keydown', function (e) {
  var open = paletteEl.className === 'on';

  // חץ־למעלה בשדה ריק, או בזמן דפדוף — היסטוריה. אחרת התנהגות רגילה.
  if (!open && e.key === 'ArrowUp' && !e.altKey
      && (histAt >= 0 || fieldEl.value === '')) {
    if (walkHistory(1)) { e.preventDefault(); return; }
  }
  if (!open && e.key === 'ArrowDown' && !e.altKey && histAt >= 0) {
    if (walkHistory(-1)) { e.preventDefault(); return; }
  }
  if (histAt >= 0 && e.key === 'Escape') {
    e.preventDefault();
    fieldEl.value = histDraft;
    resetHistory();
    return;
  }

  if (open && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
    e.preventDefault();
    picked += (e.key === 'ArrowDown' ? 1 : -1);
    if (picked < 0) { picked = shown.length - 1; }
    if (picked >= shown.length) { picked = 0; }
    refreshPalette();
    return;
  }
  if (open && e.key === 'Tab') { e.preventDefault(); complete(); return; }
  if (!open && (e.key === 'Tab' || e.key === 'ArrowRight') && !e.shiftKey
      && !e.metaKey && !e.altKey && takeGhost()) { e.preventDefault(); return; }
  if (open && e.key === 'Escape') { e.preventDefault(); closePalette(); return; }
  if (open && e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); complete(); return; }

  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    var text = fieldEl.value.trim();
    if (!text) { return; }
    fieldEl.value = '';
    closePalette();
    resetHistory();
    clipped = [];
    drawClips();
    send('send', { text: text });
  }
});

document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape' && findOn() && paletteEl.className !== 'on' && histAt < 0) {
    e.preventDefault(); clearFind(); return;
  }
  if (e.key === 'Escape' && paletteEl.className !== 'on' && histAt < 0) { send('back'); }

  // מדף: חצים בוחרים שורה, אנטר פותח אותה
  if (document.getElementById('rackview').className.indexOf('on') < 0) { return; }

  // ספרה פותחת את המסוף שמספרו כך — ר' ההסבר אצל חוגת־המספרים
  var live = document.activeElement;
  var typing = live && (live.tagName === 'INPUT' || live.tagName === 'TEXTAREA');
  if (!typing && !e.metaKey && !e.ctrlKey && !e.altKey && /^[0-9]$/.test(e.key)) {
    e.preventDefault();
    dialFeed(e.key);
    return;
  }
  if (dialBuf && e.key === 'Backspace') {
    e.preventDefault();
    dialBuf = dialBuf.slice(0, -1);
    if (dialTimer) { clearTimeout(dialTimer); dialTimer = null; }
    showDial();
    return;
  }
  if (dialBuf && e.key === 'Escape') { e.preventDefault(); dialClear(); return; }
  if (dialBuf && e.key === 'Enter') {
    e.preventDefault();
    var aimed = dialExact().concat(dialDeeper());
    if (aimed.length) { dialOpen(aimed[0]); } else { dialClear(); }
    return;
  }

  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    if (!rackRows.length) { return; }
    rackPick += (e.key === 'ArrowDown' ? 1 : -1);
    if (rackPick < 0) { rackPick = rackRows.length - 1; }
    if (rackPick >= rackRows.length) { rackPick = 0; }
    markPick();
  } else if (e.key === 'Enter' && rackPick >= 0 && rackRows[rackPick]) {
    e.preventDefault();
    rackRows[rackPick].click();
  }
});

document.getElementById('back').addEventListener('click', function () { send('back'); });
document.getElementById('findbtn').addEventListener('click', function () { send('searchOpen'); });
document.getElementById('crewback').addEventListener('click', function () { send('back'); });
/* ---------- שחזור שיחות ---------- */

function rsShow(on) {
  document.getElementById('restorewrap').className = on ? 'on' : '';
}

function openRestore() {
  document.getElementById('restorelist').textContent = '';
  document.getElementById('restorelist').appendChild(
    el('div', 'rsempty', '\(Lang.t("קורא…", "Reading…"))'));
  document.getElementById('rsnote').textContent = '';
  rsShow(true);
  send('restorable');
}

/* ⛔ נקרא מסוויפט. רשימה ריקה אינה שגיאה — היא המצב הרגיל כשכל השיחות
   כבר פתוחות, ולכן היא אומרת זאת במילים ולא בחלון ריק. */
function setRestorable(rows) {
  var box = document.getElementById('restorelist');
  box.textContent = '';
  rows = rows || [];
  if (!rows.length) {
    box.appendChild(el('div', 'rsempty', '\(Lang.t("אין שיחות לשחזור — הכל כבר פתוח", "Nothing to restore — everything is already open"))'));
    document.getElementById('rsnote').textContent = '';
    return;
  }
  rows.forEach(function (r) {
    var row = el('label', 'rsrow');
    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = false;
    cb.setAttribute('data-sid', r.sid);
    row.appendChild(cb);
    row.appendChild(el('span', 'rstitle', r.title || r.sid.slice(0, 8)));
    var when = (r.lastActive || '').slice(11, 16);
    row.appendChild(el('span', 'rsmeta', when + '  ' + (r.cwd || '')));
    box.appendChild(row);
  });
  rsNote();
}

function rsPicked() {
  var out = [];
  var boxes = document.getElementById('restorelist').querySelectorAll('input[type=checkbox]');
  for (var i = 0; i < boxes.length; i++) {
    if (boxes[i].checked) out.push(boxes[i].getAttribute('data-sid'));
  }
  return out;
}

function rsNote() {
  var n = rsPicked().length;
  /* ⚠ שמונה שניות לשיחה, וזה מכוון: פתיחה צפופה הרגה שיחות בשקט.
     אומרים את המחיר מראש כדי שהשקט לא ייראה כתקיעה. */
  document.getElementById('rsnote').textContent = n
    ? n + '\(Lang.t(" נבחרו · כ-", " selected · about "))' + (n * 8) + '\(Lang.t(" שניות", " seconds"))'
    : '\(Lang.t("בחר מה להחזיר", "Pick what to reopen"))';
  // כפתור שאי־אפשר ללחוץ עליו צריך להיראות ככזה, אחרת הלחיצה נבלעת בשקט
  document.getElementById('rsgo').className = n ? 'btn' : 'btn off';
}

/* ⛔ בזמן שחזור הכפתור ננעל. הסקריפט מרווח שמונה שניות בין חלון לחלון,
   ובלי מנעול הלחיצה השנייה — שנראית סבירה לגמרי, כי עדיין לא קרה כלום —
   מריצה סבב שני ופותחת כל שיחה פעמיים. */
var restoreBusy = false;

function restoreDone() {
  restoreBusy = false;
  var b = document.getElementById('restorebtn');
  b.className = 'btn';
  b.textContent = '\(Lang.t("שחזור", "Restore"))';
}

document.getElementById('restorebtn').addEventListener('click', function () {
  if (restoreBusy) { return; }
  openRestore();
});
document.getElementById('restorelist').addEventListener('change', rsNote);
document.getElementById('rsclose').addEventListener('click', function () { rsShow(false); });
document.getElementById('rsgo').addEventListener('click', function () {
  var sids = rsPicked();
  if (!sids.length) { return; }
  rsShow(false);
  restoreBusy = true;
  var b = document.getElementById('restorebtn');
  b.className = 'btn off';
  b.textContent = '\(Lang.t("מחזיר…", "Reopening…"))';
  send('restoreRun', { sids: sids });
});

document.getElementById('asksbtn').addEventListener('click', function () { send('asks'); });
document.getElementById('asksback').addEventListener('click', function () { send('back'); });
document.getElementById('spendbtn').addEventListener('click', function () { send('spend'); });

/* ‏**מסוף חדש.** נפתח בתיקייה של השיחה שאתה מסתכל בה, ואם אתה במדף — בבית.
   ⚠ מסך־האישור של מצב־עקיפת־ההרשאות הוא בורר, ופיץ׳ אינו עונה לבוררים:
      חלון־המסוף קופץ לחזית והתשובה נמסרת שם. */
document.getElementById('wakeall').addEventListener('click', function () {
  send('wakeAll');
});

document.getElementById('newterm').addEventListener('click', function () {
  var b = document.getElementById('newterm');
  b.textContent = '\(Lang.t("נפתח…", "opening…"))';
  setTimeout(function () { b.textContent = '\(Lang.t("+ מסוף", "+ terminal"))'; }, 2500);
  send('newTerminal');
});
document.getElementById('spendback').addEventListener('click', function () { send('back'); });

/* ‏**האפרסק הוא הכפתור שמסדר את המדף מחדש.** הסדר קפוא בכוונה, וזו הדרך
   להזיז אותו: עובדים למעלה, אחריהם ממתינים לך, ובסוף הדוממים. */
document.getElementById('logo').addEventListener('click', function () {
  document.getElementById('logo').className = 'thump';
  setTimeout(function () { document.getElementById('logo').className = ''; }, 420);
  dialClear();
  send('refresh');
});

['today', 'week', 'all'].forEach(function (key) {
  var id = key === 'today' ? 'spanday' : (key === 'week' ? 'spanweek' : 'spanall');
  document.getElementById(id).addEventListener('click', function () {
    spanKey = key;
    if (lastSpend) { paintSpend(lastSpend); }
  });
});
document.getElementById('worksback').addEventListener('click', function () { send('back'); });
(function () {
  var titleEl = document.getElementById('chattitle');
  function keep() {
    var sid = titleEl.dataset.sid || '';
    if (sid) { send('rename', { sid: sid, name: titleEl.textContent.trim(), real: true }); }
  }
  titleEl.addEventListener('blur', keep);
  titleEl.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { e.preventDefault(); titleEl.blur(); }
    if (e.key === 'Escape') { e.preventDefault(); titleEl.blur(); }
    e.stopPropagation();
  });
})();

document.getElementById('mine').addEventListener('click', toMine);
document.getElementById('bookback').addEventListener('click', function () { send('back'); });
var resumeSid = '';
document.getElementById('raise').addEventListener('click', function () {
  if (resumeSid) { send('resume', { sid: resumeSid }); return; }
  send('raise');
});
document.getElementById('docclose').addEventListener('click', closeDocAsked);
document.getElementById('docout').addEventListener('click', function () {
  if (docPathNow) { send('reveal', { path: docPathNow }); }
});

document.getElementById('docmode').addEventListener('click', function () {
  if (document.getElementById('docmode').textContent === '\(Lang.t("שמירה", "Save"))') {
    docDirty = false;
    send('saveDoc', { text: edValue() });
  } else {
    send('editDoc');
  }
});

/* לחיצה על נתיב בשיחה או במסמך פותחת אותו כאן; קישור רשת נפתח בדפדפן */
document.addEventListener('click', function (e) {
  var node = e.target;
  if (!node || node.tagName !== 'A') { return; }
  e.preventDefault();
  if (node.dataset.path) { send('openDoc', { path: node.dataset.path }); return; }
  var href = node.dataset.href || '';
  if (!href) { return; }
  if (href.indexOf('http') === 0) { send('openURL', { url: href }); }
  else { send('openDoc', { path: href }); }
});

/* שמירה במקש: המסמך נשמר גם בלי להגיע לכפתור */
document.addEventListener('keydown', function (e) {
  if ((e.metaKey || e.ctrlKey) && e.key === 's') {
    e.preventDefault();
    saveAnything();
  }
});
</script>
</body>
</html>
"""
}

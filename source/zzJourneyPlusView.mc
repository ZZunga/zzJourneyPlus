import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

typedef Font as WatchUi.FontResource or Graphics.FontDefinition;

// zzJourneyPlus (zzTravel 후속, 이름 변경) - 장거리 라이딩 / 란도너링용
//  - 메인: 주행거리 / 다음 CP 거리 / 남은거리 / 현재시각 / 경과시간
//  - 서브(위쪽 줄): 경과시간 / 구간(Lap)시간 / 도착예정(ETA) / 여유시간(Buffer) / 주행시간(Moving)
//  - 남은거리: 코스 안내 중이면 기기 내비 값, 코스 없음 또는 경로 이탈이면 설정한 목표 거리 기준
//    (목표 거리가 0이고 경로 이탈이면 마지막 코스 값에서 그 뒤 달린 거리를 빼서 이어감)
//  - 여유시간: (진행 거리 / 제한 속도) - 경과시간. 음수면 경고색
// 배터리: 문자열은 값(분 단위, 0.1km 단위)이 바뀔 때만 만들고, 폰트 폭 확인도 그때만 함
// APP_VERSION 1.0.7
class zzJourneyPlusView extends WatchUi.DataField {

    enum { M_DIST, M_NEXT, M_REMAIN, M_CLOCK, M_ELAPSED }
    // 배포 후 순서 변경 금지. 새 항목은 뒤에만 추가
    enum { S_ELAPSED, S_LAP, S_ETA, S_BUFFER, S_REMAIN, S_NEXT, S_MOVE }
    // 배경색: 0 기기 화면색에 맞춤 / 1 검정·흰색 그대로 / 2 투명
    enum { BG_AUTO, BG_PLAIN, BG_CLEAR }
    // 다음거리(NXT) = info.distanceToNextPoint.
    //  기기에서 턴바이턴 안내가 켜져 있으면 다음 턴까지, 꺼져 있으면 다음 코스 포인트까지의 거리다.
    private const SUB_TAGS    = ["ELP", "LAP", "ETA", "BUF", "REM", "NXT", "MOV"];
    // 메인 값 옆 작은 글씨 (단위 아래). 넓은 칸에서도 같은 글씨로 두 값을 구분
    private const MAIN_TAGS   = ["DST", "NXT", "REM", "TIME", "ELP"];
    // 색상표 (다른 zz 앱과 같은 인덱스, 배포 후 순서 변경 금지). 0 = 기본 글자색
    private const COLORS = [0, 0xFF0000, 0xFF55AA, 0xFF00FF, 0xFF5500, 0xFFAA00, 0x00AA00, 0x00AAFF, 0x0000FF, 0xAA00FF];
    private const ICON_COLOR = 0xFF5500;

    // ---- 설정 ----
    private var _main as Number = M_DIST;
    private var _sub as Number = S_ELAPSED;
    private var _etaMoving as Boolean = false;   // ETA 기준: false = 휴식 포함 평균, true = 이동 평균(정지 제외)
    private var _metric as Boolean = true;
    private var _is24 as Boolean = true;
    private var _unit as String = "km";
    private var _target as Float = 0.0f;         // 목표 거리 (m), 0 = 없음
    private var _limitMps as Float = 0.0f;       // 제한 속도 (m/s), 0 = 여유시간 계산 안 함
    private var _dayWarn as Number = 0xFF0000, _nightWarn as Number = 0xFF55AA;
    private var _mainTag as String = "";         // 10필드 칸에서 단위 아래 작은 글씨 (주행거리와 구분)
    private var _bgMode as Number = BG_AUTO;    // 배경색

    // ---- 상태 ----
    private var _lapStart as Number = 0;          // Lap 시작 timerTime (ms)
    private var _courseTotal as Float = 0.0f;     // 코스 전체 거리 (처음 본 남은거리 + 그때까지 주행거리)
    private var _lastRem as Float = -1.0f, _lastRemAt as Float = 0.0f;   // 마지막 코스 남은거리와 그때 주행거리
    private var _offSec as Number = 0;            // 경로 이탈 판정 연속 초 (GPS 흔들림으로 들락날락하지 않게)
    private var _onCourse as Boolean = false;     // 지금 남은거리가 코스 값인지
    // 주행시간: 타이머가 돈 시간 중 속도가 기준 이상인 구간만 더한다 (자동 일시정지를 안 써도 신호 대기는 빠짐)
    private var _moveMs as Number = 0;            // 이동시간 누적 (ms)
    private var _lastTimer as Number = -1;        // 직전 timerTime (ms), -1 = 아직 없음
    private const MOVE_MPS = 0.8f;                // 약 2.9 km/h. 이 속도 넘으면 이동으로 본다
    private const OFF_M = 50.0f;                  // 이 거리 넘게 벗어나야 이탈 후보
    private const OFF_SEC = 5;                    // 이탈 후보가 이만큼 이어져야 이탈로 판정
    private var _warn as Boolean = false;

    // ---- 문자열 캐시 ----
    private var _mainKey as Number = -9, _subKey as Number = -9;
    private var _mainI as String = "--", _mainD as String = "", _mainU as String = "";
    private var _subS as String = "--", _subU2 as String = "";
    private var _subDist as Boolean = false;
    private var _mainDirty as Boolean = true, _subDirty as Boolean = true;

    // ---- 레이아웃 ----
    private var _wide as Boolean = false, _titleOn as Boolean = true;
    // 1050 / 1060 (화면폭 480 이상). onUpdate 에서 매번 묻지 않는다
    private var _big as Boolean = false;
    private var _L as Number = 0, _T as Number = 0, _R as Number = 0, _B as Number = 0, _ug as Number = 2;
    // 10필드 칸
    private var _fMain as Font = Graphics.FONT_XTINY, _fMainDec as Font = Graphics.FONT_XTINY;
    private var _fMainT as Font = Graphics.FONT_XTINY, _fMainS as Font = Graphics.FONT_XTINY;
    private var _fUnit as Font = Graphics.FONT_XTINY, _fTag as Font = Graphics.FONT_XTINY;
    private var _fSub as Font = Graphics.FONT_XTINY, _fSubS as Font = Graphics.FONT_XTINY;
    // 깃발 아이콘('@') 윗선 (숫자 윗선과 같게)
    private var _yIconSub as Number = 0, _yIconTitle as Number = 0;
    private var _iconW as Number = 0, _tagW as Number = 0, _unitW as Number = 0, _xvLast as Number = -1;
    // 넓은 칸
    private var _fVal as Font = Graphics.FONT_XTINY, _fValS as Font = Graphics.FONT_XTINY;
    private var _fTitle as Font = Graphics.FONT_XTINY;
    private var _title as String = "zzJourneyPlus";
    private var _xTitle as Number = 0, _top as Number = 0;
    private var _xv as Number = 0, _showTag as Boolean = false;
    private var _xc1 as Number = 0, _xc2 as Number = 0, _xMid as Number = 0, _colW as Number = 0, _gap as Number = 4;
    private var _fValT as Font = Graphics.FONT_XTINY;
    // 넓은 칸: 단위/항목을 숫자 위에 둘지 (세로 여유가 있으면 위 -> 숫자가 가로를 다 씀)
    private var _above as Boolean = false, _lg as Number = 2;
    // 그리기용 선택 결과 (문자열이 바뀔 때만 다시 고름)
    private var _mf as Font = Graphics.FONT_XTINY, _my as Number = 0;
    private var _sf as Font = Graphics.FONT_XTINY, _sy as Number = 0;
    private var _dim as Number = Graphics.COLOR_DK_GRAY, _lineC as Number = Graphics.COLOR_LT_GRAY;

    function initialize() {
        DataField.initialize();
        // 업데이트 후에도 설정 화면에 현재 버전이 보이도록 덮어씀
        Application.Properties.setValue("appVersion", "1.0.7");
        readSettings();
    }

    function readSettings() as Void {
        var ds = System.getDeviceSettings();
        _metric = (ds.distanceUnits == System.UNIT_METRIC);
        _is24 = ds.is24Hour;
        _unit = _metric ? "km" : "mi";
        // 기본값: 처음 설치해도 바로 의미 있는 값이 나오도록 주행거리 + 경과시간
        _main = numProp("mainMode", M_DIST, 4);
        _sub  = numProp("subMode", S_ELAPSED, 6);
        _subDist = (_sub == S_REMAIN || _sub == S_NEXT);   // 서브가 거리면 단위(km/mi)를 단위 폰트로 그린다
        _etaMoving = (numProp("etaMode", 0, 1) == 1);
        _mainTag = MAIN_TAGS[_main] as String;
        var perUnit = _metric ? 1000.0f : 1609.344f;
        _target   = floatProp("targetDistance") * perUnit;
        _limitMps = floatProp("limitSpeed") * perUnit / 3600.0f;
        _dayWarn   = COLORS[numProp("dayHighColor", 1, 9)] as Number;
        _nightWarn = COLORS[numProp("nightHighColor", 2, 9)] as Number;
        _bgMode = numProp("bgMode", BG_AUTO, 2);
        _mainKey = -9; _subKey = -9;
    }

    private function numProp(k as String, def as Number, max as Number) as Number {
        var v = Application.Properties.getValue(k);
        return (v instanceof Number && v >= 0 && v <= max) ? v : def;
    }

    private function floatProp(k as String) as Float {
        var v = Application.Properties.getValue(k);
        if (v instanceof Float || v instanceof Number) {
            var f = v.toFloat();
            return (f > 0.0f) ? f : 0.0f;
        }
        return 0.0f;
    }

    // =========================================================
    // 레이아웃
    // =========================================================
    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        var sw = System.getDeviceSettings().screenWidth;
        _wide = w > sw * 0.75f;
        _big = (sw >= 480);
        _L = (w * 0.05f + 0.5f).toNumber();
        _T = (h * 0.05f + 0.5f).toNumber();
        _R = w - _L;
        _B = h - _T;
        _ug = (w * 0.02f).toNumber(); if (_ug < 2) { _ug = 2; }
        // 폰트는 지금 레이아웃에 필요한 것만 둠
        _fMain = Graphics.FONT_XTINY; _fMainDec = Graphics.FONT_XTINY; _fMainT = Graphics.FONT_XTINY;
        _fMainS = Graphics.FONT_XTINY; _fUnit = Graphics.FONT_XTINY; _fTag = Graphics.FONT_XTINY;
        _fSub = Graphics.FONT_XTINY; _fSubS = Graphics.FONT_XTINY;
        _fVal = Graphics.FONT_XTINY; _fValS = Graphics.FONT_XTINY; _fTitle = Graphics.FONT_XTINY;
        if (_wide) { layoutWide(dc, w, h); } else {
            // 좁은 칸: 오른쪽 여백만 3% (메인 거리·태그를 오른쪽으로)
            _R = w - (w * 0.03f + 0.5f).toNumber();
            layoutCell(dc);
        }
        _mainDirty = true; _subDirty = true;
    }

    private function layoutCell(dc as Graphics.Dc) as Void {
        _fMain    = loadFont(Rez.Fonts.C10Main);
        _fMainDec = loadFont(Rez.Fonts.C10MainDec);
        _fMainT   = loadFont(Rez.Fonts.C10MainT);
        _fMainS   = loadFont(Rez.Fonts.C10MainS);
        _fUnit    = loadFont(Rez.Fonts.C10Unit);
        _fSub     = loadFont(Rez.Fonts.C10Sub);
        _fSubS    = loadFont(Rez.Fonts.C10SubS);
        _fTag     = loadFont(Rez.Fonts.C10Tag);
        _iconW = dc.getTextWidthInPixels("@", _fSub);
        _yIconSub = iconTop(_fSub);
        _tagW  = maxW(dc, ["ELP", "LAP", "ETA", "BUF", "REM", "NXT", "MOV", "AM", "PM"], _fTag) + _ug;
        _unitW = maxW(dc, ["km", "mi", "AM", "PM"], _fUnit);
        var tw = maxW(dc, ["REM", "NXT"], _fTag);
        _unitW = ((tw > _unitW) ? tw : _unitW) + _ug;
    }

    // 깃발 아이콘('@')은 숫자보다 크다. 윗선을 숫자 윗선(_T)에 맞추고 아래로 내려 그림
    // (가운데 맞춤이면 칸 위로 튀어나와 보여서)
    private function iconTop(f as Font) as Number {
        return _T;
    }

    private function layoutWide(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var fv = loadFont(Rez.Fonts.WideVal);
        var fs = loadFont(Rez.Fonts.WideValS);
        var ft = loadFont(Rez.Fonts.WideTitle);
        var vg = (h * 0.05f).toNumber(); if (vg < 2) { vg = 2; }
        _yIconTitle = iconTop(ft);
        var hTitle = _yIconTitle + Graphics.getFontHeight(ft) - _T;      // 아이콘 아래 끝까지
        var hDesc  = (Graphics.getFontAscent(ft) * 1.3f).toNumber();   // 'y' 꼬리
        if (hTitle < hDesc) { hTitle = hDesc; }
        var hu = _B - _T;
        _titleOn = (hu - hTitle - vg) >= Graphics.getFontAscent(fs);
        if (_titleOn) {
            _fTitle = ft;
            _title = (w < 300) ? "zzJourney+" : "zzJourneyPlus";
            _xTitle = _L + dc.getTextWidthInPixels("@", _fTitle);
            _top = _T + hTitle + vg;
        } else {
            _top = _T;
        }
        // 숫자 줄 높이에 맞는 폰트만
        // 값 옆 단위/태그 (10필드 칸과 같은 글씨)
        _fUnit = loadFont(Rez.Fonts.C10Unit);
        _fTag  = loadFont(Rez.Fonts.C10Tag);
        var room = _B - _top;
        var aT = Graphics.getFontAscent(_fTag);
        _lg = aT / 3; if (_lg < 2) { _lg = 2; }
        _above = (Graphics.getFontAscent(fv) + _lg + aT <= room);
        _fVal  = (Graphics.getFontAscent(fv) <= room) ? fv : fs;
        _fValS = fs;
        _fValT = loadFont(Rez.Fonts.C10MainS);
        if (Graphics.getFontAscent(fs) > room) { _fVal = _fValT; _fValS = _fVal; }
        var gap = (w * 0.04f).toNumber(); if (gap < 4) { gap = 4; }
        _gap = gap;
        _xMid = w / 2;
        _xc1 = (_L + _xMid - gap / 2) / 2;
        _xc2 = (_xMid + gap / 2 + _R) / 2;
        _colW = _xMid - gap / 2 - _L;
    }

    private function loadFont(id as Lang.ResourceId) as Font {
        return WatchUi.loadResource(id) as WatchUi.FontResource;
    }

    private function maxW(dc as Graphics.Dc, a as Array<String>, f as Font) as Number {
        var m = 0;
        for (var i = 0; i < a.size(); i++) {
            var x = dc.getTextWidthInPixels(a[i], f);
            if (x > m) { m = x; }
        }
        return m;
    }

    // =========================================================
    // 계산 (1초마다)
    // =========================================================
    function onTimerLap() as Void {
        var info = Activity.getActivityInfo();
        var t = (info != null) ? info.timerTime : null;
        _lapStart = (t != null) ? t : 0;
    }

    function onTimerReset() as Void {
        _lapStart = 0; _courseTotal = 0.0f; _lastRem = -1.0f; _lastRemAt = 0.0f; _offSec = 0; _onCourse = false;
        _moveMs = 0; _lastTimer = -1;
    }

    function compute(info as Activity.Info) as Void {
        var dv = info.elapsedDistance;
        var dist = (dv != null) ? dv : 0.0f;
        var ev = info.elapsedTime;
        var elapsed = (ev != null) ? ev : 0;
        var rem = remaining(info, dist);
        addMoving(info);

        // ---- 메인 ----
        if (_main == M_CLOCK) {
            var ct = System.getClockTime();
            setMainTime(ct.hour * 60 + ct.min, true);
        } else if (_main == M_ELAPSED) {
            setMainTime(elapsed / 60000, false);
        } else {
            var m = null as Float?;
            if (_main == M_DIST) { m = dist; }
            else if (_main == M_NEXT) { m = info.distanceToNextPoint; }
            else { m = rem; }
            setMainDist(m);
        }

        // ---- 서브 ----
        var key = -1, neg = false;
        if (_sub == S_ELAPSED) {
            key = elapsed / 60000;
        } else if (_sub == S_LAP) {
            var tv = info.timerTime;
            var t = (tv != null) ? tv : 0;
            key = (t > _lapStart) ? (t - _lapStart) / 60000 : 0;
        } else if (_sub == S_MOVE) {
            key = _moveMs / 60000;
        } else if (_sub == S_ETA) {
            // 평균 속도: 기본은 휴식 포함(주행거리 / 경과시간), 설정에서 이동 평균(정지 제외)
            var spd = 0.0f;
            if (_etaMoving) {
                var a = info.averageSpeed;
                if (a != null) { spd = a; }
            } else if (elapsed > 60000) {
                spd = dist * 1000.0f / elapsed;
            }
            if (rem != null && dist > 100.0f && spd > 0.5f) {
                var secLeft = rem / spd;
                if (secLeft < 360000.0f) {
                    var ct = System.getClockTime();
                    key = ((ct.hour * 3600 + ct.min * 60 + ct.sec + secLeft.toNumber()) / 60) % 1440;
                }
            }
        } else if (_subDist) {
            // 남은거리 / 다음 CP 까지 거리: 서브는 정수 (소수점 없음)
            var dm = (_sub == S_REMAIN) ? rem : info.distanceToNextPoint;
            key = (dm == null) ? -1 : (dm / (_metric ? 1000.0f : 1609.344f) + 0.5f).toNumber();
        } else {
            if (_limitMps > 0.0f) {
                // 진행거리: 코스를 따라가는 중이면 코스 기준(우회 거리는 빼고), 아니면 주행거리
                // 목표 거리는 남은거리에만 쓰고 진행거리에는 섞지 않음 (코스 길이와 달라도 시작부터 마이너스가 되지 않게)
                var prog = dist;
                if (_courseTotal > 0.0f && _lastRem >= 0.0f) {
                    prog = _courseTotal - (_onCourse ? _lastRem : (_lastRem - (dist - _lastRemAt)));
                    if (prog > dist) { prog = dist; }
                }
                if (prog < 0.0f) { prog = 0.0f; }
                var buf = (prog / _limitMps).toNumber() - elapsed / 1000;     // 초
                neg = (buf < 0);
                key = (neg ? -buf : buf) / 60;
                if (neg) { key = -key - 1; }                                      // 음수는 -1부터 (0:00 이하 구분)
            }
        }
        _warn = (_sub == S_BUFFER) && neg;
        if (key != _subKey) {
            _subKey = key;
            _subU2 = "";
            if (_sub == S_ETA) {
                if (key < 0) { _subS = "--:--"; }
                else {
                    _subS = clockStr(key);
                    if (!_is24) { _subU2 = (key < 720) ? "AM" : "PM"; }
                }
            } else if (_subDist) {
                _subS = (key < 0) ? "--" : key.toString();
                _subU2 = _unit;
            } else if (_sub == S_BUFFER) {
                if (_limitMps <= 0.0f) { _subS = "--:--"; }
                else if (key < 0) { _subS = "-" + durStr(-key - 1); }
                else { _subS = "+" + durStr(key); }
            } else {
                _subS = durStr(key);
            }
            _subDirty = true;
        }
    }

    // 주행시간 누적: 타이머가 돈 시간만 보고, 그중 속도가 기준 이상인 구간만 더한다
    //  일시정지 중에는 timerTime 이 멈추고, 타이머가 돌아도 신호 대기처럼 멈춘 시간은 빠진다
    private function addMoving(info as Activity.Info) as Void {
        var tv = info.timerTime;
        var t = (tv != null) ? tv : 0;
        if (_lastTimer >= 0 && t > _lastTimer) {
            var sv = info.currentSpeed;
            if (sv != null && sv > MOVE_MPS) { _moveMs += t - _lastTimer; }
        }
        _lastTimer = t;
    }

    // 남은거리 (m)
    //  1) 코스 안내 중이면 기기 내비 값
    //  2) 코스를 따라가다 이탈하면 마지막 코스 남은거리에서 그 뒤 달린 거리를 빼서 이어감 (값이 튀지 않게)
    //  3) 코스를 한 번도 안 썼으면 목표 거리 - 주행거리
    private function remaining(info as Activity.Info, dist as Float) as Float? {
        var dtd = info.distanceToDestination;
        var offNow = false;
        if (info has :offCourseDistance) {
            var oc = info.offCourseDistance;
            offNow = (oc != null && oc > OFF_M);
        }
        // 잠깐 벗어난 것(교차로, GPS 흔들림)은 이탈로 보지 않음. 복귀는 바로 인정
        _offSec = offNow ? _offSec + 1 : 0;
        _onCourse = (dtd != null && _offSec < OFF_SEC);
        if (_onCourse) {
            var d = dtd as Float;
            if (_courseTotal <= 0.0f && d > 0.0f) { _courseTotal = dist + d; }
            _lastRem = d; _lastRemAt = dist;
            return d;
        }
        if (_lastRem >= 0.0f) {
            var r = _lastRem - (dist - _lastRemAt);
            return (r > 0.0f) ? r : 0.0f;
        }
        if (_target > 0.0f) {
            var r = _target - dist;
            return (r > 0.0f) ? r : 0.0f;
        }
        return null;
    }

    private function setMainDist(m as Float?) as Void {
        var v10 = (m == null) ? -1 : (m / (_metric ? 100.0f : 160.9344f) + 0.5f).toNumber();
        if (v10 == _mainKey) { return; }
        _mainKey = v10;
        _mainU = _unit;
        if (v10 < 0)         { _mainI = "--"; _mainD = ""; }
        else if (v10 >= 1000) { _mainI = (v10 / 10).toString(); _mainD = ""; }    // 100 이상은 정수
        else                  { _mainI = (v10 / 10).toString(); _mainD = "." + (v10 % 10); }
        _mainDirty = true;
    }

    private function setMainTime(min as Number, clock as Boolean) as Void {
        if (min == _mainKey) { return; }
        _mainKey = min;
        _mainD = "";
        if (clock) {
            _mainI = clockStr(min);
            _mainU = _is24 ? "" : ((min < 720) ? "AM" : "PM");
        } else {
            _mainI = durStr(min);
            _mainU = "";
        }
        _mainDirty = true;
    }

    private function durStr(min as Number) as String {
        return (min / 60).toString() + ":" + (min % 60).format("%02d");
    }

    // 하루 중 분 → "14:35" / 12시간이면 "2:35" (오전/오후는 따로 표시)
    private function clockStr(min as Number) as String {
        var h = min / 60;
        if (!_is24) { h = h % 12; if (h == 0) { h = 12; } }
        return h.toString() + ":" + (min % 60).format("%02d");
    }

    // =========================================================
    // 그리기
    // =========================================================
    function onUpdate(dc as Graphics.Dc) as Void {
        var sys = getBackgroundColor();
        var sysClear = (sys == Graphics.COLOR_TRANSPARENT);   // 기기가 "투명"이라고 알려준 경우
        var night = (sys == Graphics.COLOR_BLACK || sysClear);
        var soft = (_bgMode == BG_AUTO) && _big;   // _big = 1050 / 1060
        var fg = night ? Graphics.COLOR_WHITE
                       : (soft ? 0x313152 : Graphics.COLOR_BLACK);
        var bg = night ? (soft ? 0x17181D : Graphics.COLOR_BLACK)
                       : (soft ? 0xDCDCDC : Graphics.COLOR_WHITE);
        if (_bgMode == BG_CLEAR || (_bgMode == BG_AUTO && sysClear)) {
            bg = Graphics.COLOR_TRANSPARENT;
        }
        dc.setColor(fg, bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        var sc = fg;
        if (_warn) { var c = night ? _nightWarn : _dayWarn; if (c != 0) { sc = c; } }
        // 보조 글자색: 야간에는 진회색이 안 보이므로 밝은 회색
        _dim = night ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
        _lineC = night ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;
        if (_wide) { drawWide(dc, fg, sc); } else { drawCell(dc, fg, sc); }
    }

    private function drawCell(dc as Graphics.Dc, fg as Number, sc as Number) as Void {
        var hasU = (_mainU.length() > 0);
        if (_mainDirty) {
            // 메인 값은 단위/태그 바로 왼쪽에 오른쪽 정렬 (다른 zz+ 앱과 같게).
            // 태그(DIST/CP/REM/TIME/ELP)는 단위 아래. 넣으면 메인 글씨가 작아지는 경우엔 뺀다.
            var col = hasU ? dc.getTextWidthInPixels(_mainU, _fUnit) : 0;
            _showTag = false;
            var tw = dc.getTextWidthInPixels(_mainTag, _fTag);
            var c2 = (tw > col) ? tw : col;
            var vOk = !hasU || (Graphics.getFontAscent(_fUnit) + Graphics.getFontAscent(_fTag) < Graphics.getFontAscent(_fMain));
            var wOk = (_mainD.length() > 0) || (dc.getTextWidthInPixels(_mainI, _fMain) <= _R - c2 - _ug - _L);
            if (_mainTag.length() > 0 && vOk && wOk) { _showTag = true; col = c2; }
            _xv = (col > 0) ? (_R - col - _ug) : _R;
        }
        var xv = _xv;
        // 서브 태그 폭도 지금 표시하는 태그 기준
        var tagW = dc.getTextWidthInPixels(SUB_TAGS[_sub] as String, _fTag);
        if (_subU2.length() > 0) {
            var t2 = dc.getTextWidthInPixels(_subU2, _subDist ? _fUnit : _fTag);
            if (t2 > tagW) { tagW = t2; }
        }
        tagW += _ug;
        if (tagW != _tagW) { _tagW = tagW; _subDirty = true; }
        if (_mainDirty) {
            // 큰 폰트 → 시간용 → 작은 폰트 순으로 폭에 맞는 것
            var avail = xv - _L;
            if (_mainD.length() > 0 || dc.getTextWidthInPixels(_mainI, _fMain) <= avail) { _mf = _fMain; }
            else if (dc.getTextWidthInPixels(_mainI, _fMainT) <= avail) { _mf = _fMainT; }
            else { _mf = _fMainS; }
            _my = _B - Graphics.getFontAscent(_mf);
            _mainDirty = false;
        }
        if (_subDirty) {
            // 깃발 글리프 오른쪽 여백(advance 의 약 1/8)은 겹쳐도 됨
            var avail = _R - tagW - _L - _iconW + _iconW / 8;
            _sf = (dc.getTextWidthInPixels(_subS, _fSub) <= avail) ? _fSub : _fSubS;
            _sy = _T + Graphics.getFontAscent(_fSub) - Graphics.getFontAscent(_sf);
            _subDirty = false;
        }

        // 위쪽 줄: 아이콘 + 서브 값 + 태그
        dc.setColor(ICON_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_L, _yIconSub, _fSub, "@", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(sc, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_R - tagW, _sy, _sf, _subS, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        var aSub = Graphics.getFontAscent(_fSub);
        dc.drawText(_R, _T, _fTag, SUB_TAGS[_sub] as String, Graphics.TEXT_JUSTIFY_RIGHT);
        if (_subU2.length() > 0) {
            var uf = _subDist ? _fUnit : _fTag;
            dc.drawText(_R, _T + aSub - Graphics.getFontAscent(uf), uf, _subU2, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // 아래쪽: 메인 값 + 단위
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var x = xv;
        if (_mainD.length() > 0) {
            dc.drawText(x, _B - Graphics.getFontAscent(_fMainDec), _fMainDec, _mainD, Graphics.TEXT_JUSTIFY_RIGHT);
            x -= dc.getTextWidthInPixels(_mainD, _fMainDec);
        }
        dc.drawText(x, _my, _mf, _mainI, Graphics.TEXT_JUSTIFY_RIGHT);
        if (hasU) {
            // 단위는 메인 값 윗선에 맞춤 (거리 단위 / 오전·오후)
            dc.drawText(_R, _my, _fUnit, _mainU, Graphics.TEXT_JUSTIFY_RIGHT);
        }
        if (_showTag) {
            // 무엇을 보여주는지 (DIST / CP / REM / TIME / ELP): 바닥선에 맞춤
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_R, _B - Graphics.getFontAscent(_fTag), _fTag, _mainTag, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    private function drawWide(dc as Graphics.Dc, fg as Number, sc as Number) as Void {
        if (_titleOn) {
            dc.setColor(ICON_COLOR, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_L, _yIconTitle, _fTitle, "@", Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_xTitle, _T, _fTitle, _title, Graphics.TEXT_JUSTIFY_LEFT);
        }
        // 각 값 오른쪽에 10필드 칸과 같은 작은 글씨: 위 = 단위 / 태그, 아래 = 무엇인지 / 오전·오후
        var ms = _mainI + _mainD;
        var mt1W = dc.getTextWidthInPixels(_mainU, _fUnit);
        var mt2W = dc.getTextWidthInPixels(_mainTag, _fTag);
        var mtW = _above ? 0 : ((mt1W > mt2W) ? mt1W : mt2W) + _ug;
        var st1 = SUB_TAGS[_sub] as String;
        var st1W = dc.getTextWidthInPixels(st1, _fTag);
        var sUF = _subDist ? _fUnit : _fTag;
        var st2W = dc.getTextWidthInPixels(_subU2, sUF);
        var stW = _above ? 0 : ((st1W > st2W) ? st1W : st2W) + _ug;
        if (_mainDirty || _subDirty) {
            // 두 값은 같은 크기. 큰 글씨부터 둘 다 들어가는 것을 고르고,
            // 칸은 반반이 아니라 내용 폭에 맞춰 나눔 (1000km 같은 긴 거리도 큰 글씨 유지)
            var fonts = [_fVal, _fValS, _fValT];
            var mg = 0, sg = 0;
            var f = _fValT;
            for (var i = 0; i < 3; i++) {
                f = fonts[i] as Font;
                mg = dc.getTextWidthInPixels(ms, f) + mtW;
                sg = dc.getTextWidthInPixels(_subS, f) + stW;
                if (mg + sg + _gap * 3 <= _R - _L) { break; }
            }
            _mf = f; _sf = f;
            var half = (_R - _L - _gap) / 2 - _ug * 2;
            if (mg <= half && sg <= half) {
                _xMid = (_L + _R) / 2;                // 반반에 들어가면 가운데 고정
            } else {
                var free = _R - _L - mg - sg;
                if (free < 0) { free = 0; }
                _xMid = _L + mg + free / 2;
            }
            _xc1 = (_L + _xMid) / 2;
            _xc2 = (_xMid + _R) / 2;
            _mainDirty = false; _subDirty = false;
        }
        // 두 값의 바닥선을 맞춤, 남는 세로 공간의 가운데
        var a = Graphics.getFontAscent(_fVal);
        var aTag = Graphics.getFontAscent(_fTag);
        var aUnit = Graphics.getFontAscent(_fUnit);
        var base;
        if (_above) {
            var tot = aTag + _lg + a;
            base = _top + (_B - _top - tot) / 2 + tot;
        } else {
            base = _top + (_B - _top - a) / 2 + a;
        }

        // ---- 메인 ----
        var vw = dc.getTextWidthInPixels(ms, _mf);
        var vTop = base - Graphics.getFontAscent(_mf);
        var xr;
        if (_above) {
            // 숫자는 칸 가운데, 위에 "DST km" (항목은 흐리게, 단위는 진하게) 숫자 오른쪽 끝에 맞춤
            xr = _xc1 + vw / 2;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xr, vTop, _mf, ms, Graphics.TEXT_JUSTIFY_RIGHT);
            var lb = vTop - _lg;
            var x = xr;
            if (mt1W > 0) {
                dc.drawText(x, lb - aUnit, _fUnit, _mainU, Graphics.TEXT_JUSTIFY_RIGHT);
                x -= mt1W + _ug * 2;
            }
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, lb - aTag, _fTag, _mainTag, Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            xr = _xc1 + (vw + mtW) / 2 - mtW;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xr, vTop, _mf, ms, Graphics.TEXT_JUSTIFY_RIGHT);
            if (mt1W > 0) {
                dc.drawText(xr + _ug, vTop, _fUnit, _mainU, Graphics.TEXT_JUSTIFY_LEFT);
            }
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xr + _ug, base - aTag, _fTag, _mainTag, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // ---- 서브 ----
        vw = dc.getTextWidthInPixels(_subS, _sf);
        vTop = base - Graphics.getFontAscent(_sf);
        if (_above) {
            xr = _xc2 + vw / 2;
            dc.setColor(sc, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xr, vTop, _sf, _subS, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            if (_subDist && st2W > 0) {
                // 거리 단위는 단위 폰트 (태그 폰트에는 소문자가 없다). 아랫선을 태그와 맞춤
                dc.drawText(xr, vTop - _lg - Graphics.getFontAscent(sUF), sUF, _subU2, Graphics.TEXT_JUSTIFY_RIGHT);
                dc.drawText(xr - st2W - _ug, vTop - _lg - aTag, _fTag, st1, Graphics.TEXT_JUSTIFY_RIGHT);
            } else {
                var t = (st2W > 0) ? (st1 + " " + _subU2) : st1;
                dc.drawText(xr, vTop - _lg - aTag, _fTag, t, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        } else {
            xr = _xc2 + (vw + stW) / 2 - stW;
            dc.setColor(sc, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xr, vTop, _sf, _subS, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xr + _ug, vTop, _fTag, st1, Graphics.TEXT_JUSTIFY_LEFT);
            if (st2W > 0) {
                dc.drawText(xr + _ug, base - Graphics.getFontAscent(sUF), sUF, _subU2, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }

        dc.setColor(_lineC, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_xMid, _top, _xMid, _B);
    }
}

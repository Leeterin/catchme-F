package com.catchme.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;

// 홈 화면 위젯(소/중/대)이 같이 쓰는 그리기 로직
// 소: 바로 다음 약속 1개 / 중: 3개 / 대: 다음 약속 크게 + 5개 더
public class WidgetRenderer {
    static final String PREFS = "catchme_widget";
    static final String KEY = "widgetData";
    static final String[] WEEKDAYS = {"일", "월", "화", "수", "목", "금", "토"};

    static class Item {
        String title, timeLabel, places;
        long dayMs;
        long expiresMs;
    }

    static void saveData(Context ctx, String json) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply();
    }

    static void refreshAll(Context ctx) {
        AppWidgetManager mgr = AppWidgetManager.getInstance(ctx);
        Class<?>[] providers = {CatchmeWidgetSmall.class, CatchmeWidgetMedium.class, CatchmeWidgetLarge.class};
        for (Class<?> p : providers) {
            int[] ids = mgr.getAppWidgetIds(new ComponentName(ctx, p));
            for (int id : ids) update(ctx, mgr, id, p);
        }
    }

    static boolean loggedIn = false;

    // 끝난 약속은 빼고 남은 것만 (시간이 없는 약속은 그날 자정까지 보여줌)
    static List<Item> loadItems(Context ctx) {
        List<Item> list = new ArrayList<>();
        loggedIn = false;
        String json = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null);
        if (json == null) return list;
        try {
            JSONObject root = new JSONObject(json);
            loggedIn = root.optBoolean("loggedIn", false);
            JSONArray arr = root.optJSONArray("items");
            long now = System.currentTimeMillis();
            for (int i = 0; arr != null && i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                Item it = new Item();
                it.title = o.optString("title", "약속");
                it.timeLabel = o.optString("timeLabel", "");
                it.places = o.optString("places", "");
                it.dayMs = (long) o.optDouble("dayMs", 0);
                it.expiresMs = o.isNull("endMs") ? it.dayMs + 86400000L : (long) o.optDouble("endMs", 0);
                if (it.expiresMs > now) list.add(it);
            }
        } catch (Exception ignored) {
        }
        return list;
    }

    static int daysFromToday(long dayMs) {
        Calendar today = Calendar.getInstance();
        today.set(Calendar.HOUR_OF_DAY, 0);
        today.set(Calendar.MINUTE, 0);
        today.set(Calendar.SECOND, 0);
        today.set(Calendar.MILLISECOND, 0);
        return (int) Math.round((dayMs - today.getTimeInMillis()) / 86400000.0);
    }

    // 오늘 / 내일 / 금요일 / 10/12 - 웹 홈 화면과 같은 규칙
    static String dayLabel(long dayMs) {
        int diff = daysFromToday(dayMs);
        if (diff == 0) return "오늘";
        if (diff == 1) return "내일";
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(dayMs);
        if (diff > 1 && diff < 7) return WEEKDAYS[c.get(Calendar.DAY_OF_WEEK) - 1] + "요일";
        return (c.get(Calendar.MONTH) + 1) + "/" + c.get(Calendar.DAY_OF_MONTH);
    }

    static String dDay(long dayMs) {
        int diff = daysFromToday(dayMs);
        return diff <= 0 ? "D-DAY" : "D-" + diff;
    }

    static String subLine(Item it) {
        String place = it.places.isEmpty() ? "장소 미정" : it.places;
        return it.timeLabel.isEmpty() ? place : it.timeLabel + " · " + place;
    }

    static void update(Context ctx, AppWidgetManager mgr, int widgetId, Class<?> provider) {
        List<Item> items = loadItems(ctx);
        RemoteViews views;
        if (provider == CatchmeWidgetSmall.class) {
            views = new RemoteViews(ctx.getPackageName(), R.layout.widget_small);
            if (!items.isEmpty()) {
                Item it = items.get(0);
                views.setTextViewText(R.id.w_day, dayLabel(it.dayMs));
                views.setTextViewText(R.id.w_dday, dDay(it.dayMs));
                views.setTextViewText(R.id.w_title, it.title);
                views.setTextViewText(R.id.w_time, it.timeLabel);
                views.setViewVisibility(R.id.w_time, it.timeLabel.isEmpty() ? View.GONE : View.VISIBLE);
                views.setTextViewText(R.id.w_place, it.places.isEmpty() ? "장소 미정" : it.places);
            }
        } else {
            boolean large = provider == CatchmeWidgetLarge.class;
            views = new RemoteViews(ctx.getPackageName(), large ? R.layout.widget_large : R.layout.widget_medium);
            views.setTextViewText(R.id.w_count, items.size() + "개");
            int start = 0;
            if (large && !items.isEmpty()) {
                // 바로 다음 약속은 크게
                Item first = items.get(0);
                views.setTextViewText(R.id.w_day, dayLabel(first.dayMs));
                views.setTextViewText(R.id.w_dday, dDay(first.dayMs));
                views.setTextViewText(R.id.w_title, first.title);
                views.setTextViewText(R.id.w_sub, subLine(first));
                start = 1;
            }
            int max = large ? 5 : 3;
            views.removeAllViews(R.id.w_list);
            for (int i = start; i < items.size() && i < start + max; i++) {
                Item it = items.get(i);
                RemoteViews row = new RemoteViews(ctx.getPackageName(), R.layout.widget_row);
                row.setTextViewText(R.id.r_day, dayLabel(it.dayMs));
                row.setTextViewText(R.id.r_title, it.title);
                row.setTextViewText(R.id.r_sub, subLine(it));
                views.addView(R.id.w_list, row);
            }
        }
        boolean empty = items.isEmpty();
        views.setViewVisibility(R.id.w_content, empty ? View.GONE : View.VISIBLE);
        views.setViewVisibility(R.id.w_empty, empty ? View.VISIBLE : View.GONE);
        views.setTextViewText(R.id.w_empty_title, loggedIn ? "잡힌 약속이 없어요" : "로그인하면\n약속이 보여요");
        views.setTextViewText(R.id.w_empty_hint, loggedIn ? "탭해서 약속 잡기" : "탭해서 앱 열기");

        // 위젯 어디를 눌러도 앱이 열림
        Intent intent = new Intent(ctx, MainActivity.class);
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(ctx, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.w_root, pi);

        mgr.updateAppWidget(widgetId, views);
    }
}

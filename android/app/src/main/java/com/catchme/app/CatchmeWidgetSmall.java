package com.catchme.app;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;

// 홈 화면 위젯 - 그리는 건 WidgetRenderer가 함
public class CatchmeWidgetSmall extends AppWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) WidgetRenderer.update(context, manager, id, CatchmeWidgetSmall.class);
    }
}

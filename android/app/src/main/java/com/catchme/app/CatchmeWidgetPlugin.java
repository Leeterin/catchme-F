package com.catchme.app;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

// 웹 화면이 넘겨준 "다가오는 약속" 목록을 저장해두고 홈 화면 위젯들을 새로 그림
@CapacitorPlugin(name = "CatchmeWidget")
public class CatchmeWidgetPlugin extends Plugin {
    @PluginMethod
    public void update(PluginCall call) {
        String data = call.getString("data");
        if (data == null) {
            call.reject("data가 없어요");
            return;
        }
        WidgetRenderer.saveData(getContext(), data);
        WidgetRenderer.refreshAll(getContext());
        call.resolve();
    }
}

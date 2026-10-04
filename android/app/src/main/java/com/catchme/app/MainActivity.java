package com.catchme.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // 앱 안에 직접 만든 플러그인(홈 화면 위젯 연동)은 자동 등록이 안 돼서 여기서 등록 - super.onCreate보다 먼저 해야 함
        registerPlugin(CatchmeWidgetPlugin.class);
        super.onCreate(savedInstanceState);
    }
}

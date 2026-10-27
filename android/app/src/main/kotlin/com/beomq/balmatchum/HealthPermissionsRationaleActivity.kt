package com.beomq.balmatchum

import android.app.Activity
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Opened by Health Connect's privacy/rationale link, never requests permission itself. */
class HealthPermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "걸음 데이터 사용 안내"
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val inset = (24 * resources.displayMetrics.density).toInt()
            setPadding(inset, inset, inset, inset)
        }
        content.addView(TextView(this).apply {
            textSize = 18f
            setTextIsSelectable(true)
            text = """
                발맞춤 걸음 데이터 사용 안내

                Health Connect의 걸음 수 읽기 권한만 요청합니다. 사용자가 걸음 새로고침이나 서버 동기화를 누를 때 한국 시간 오늘 0시부터 현재까지의 총 걸음 수를 조회합니다.

                오늘 걸음 표시, 일일 목표 달성 확인, 걸음 보상 계산에 사용합니다. 로그인 후 서버 동기화 시 날짜와 총 걸음 수가 발맞춤 서버에 전송됩니다. 개별 센서 기록이나 다른 건강 데이터는 읽지 않습니다.

                걸음 데이터는 광고 타기팅에 사용하지 않습니다. Health Connect에 데이터를 쓰거나 백그라운드에서 읽지 않습니다.

                권한을 거부해도 앱의 다른 기능은 이용할 수 있습니다. Android 설정의 Health Connect → 앱 권한 → 발맞춤에서 언제든 걸음 권한을 해제할 수 있습니다.
            """.trimIndent()
        })
        setContentView(ScrollView(this).apply { addView(content) })
    }
}

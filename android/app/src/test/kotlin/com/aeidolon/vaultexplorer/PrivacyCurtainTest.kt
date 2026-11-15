package com.aeidolon.vaultexplorer

import android.app.Activity
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PrivacyCurtainTest {

    private lateinit var activity: Activity
    private lateinit var privacyCurtain: PrivacyCurtain

    @Before
    fun setUp() {
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        privacyCurtain = PrivacyCurtain(activity)
        privacyCurtain.install()
    }

    private fun getCurtainView(): View? {
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        return if (root.childCount > 0) root.getChildAt(root.childCount - 1) else null
    }

    @Test
    fun `install creates a GONE curtain view`() {
        val curtain = getCurtainView()
        assertNotNull("Curtain view should be attached to root", curtain)
        assertEquals(View.GONE, curtain!!.visibility)
    }

    @Test
    fun `show makes curtain view VISIBLE`() {
        privacyCurtain.show()
        val curtain = getCurtainView()
        assertEquals(View.VISIBLE, curtain!!.visibility)
    }

    @Test
    fun `armPendingReveal and onResumedFramePainted hides curtain`() {
        privacyCurtain.show()
        assertEquals(View.VISIBLE, getCurtainView()!!.visibility)

        privacyCurtain.armPendingReveal()
        privacyCurtain.onResumedFramePainted()

        assertEquals(View.GONE, getCurtainView()!!.visibility)
    }

    @Test
    fun `onResumedFramePainted before armPendingReveal reveals immediately once armed`() {
        privacyCurtain.show()
        assertEquals(View.VISIBLE, getCurtainView()!!.visibility)

        // Dart sends frame painted signal before Activity arms reveal
        privacyCurtain.onResumedFramePainted()
        // Window focus or onResume arrives
        privacyCurtain.armPendingReveal()

        assertEquals(View.GONE, getCurtainView()!!.visibility)
    }

    @Test
    fun `armPendingReveal falls back to safety net timeout if Dart signal is missed`() {
        privacyCurtain.show()
        assertEquals(View.VISIBLE, getCurtainView()!!.visibility)

        privacyCurtain.armPendingReveal(safetyNetMs = 100L)
        assertEquals(View.VISIBLE, getCurtainView()!!.visibility)

        // Fast-forward Looper past the safety-net delay
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(150))

        assertEquals(View.GONE, getCurtainView()!!.visibility)
    }
}

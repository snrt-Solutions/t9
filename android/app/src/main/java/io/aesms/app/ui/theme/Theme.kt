package io.aesms.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.aesms.app.R

object T9Theme {
    val bg = Color(0xFFF4F4F4)
    val surface = Color.White
    val ink = Color(0xFF0B0B0B)
    val muted = Color(0xFF9AA0A6)
    val accent = Color(0xFF0066FF)
    /** Success / live — CI has no teal; use accent. */
    val teal = accent
    val warn = Color(0xFFC45C1A)
    val hair = ink
    val stroke = 1.dp
    val rule = 1.5.dp
    val space1 = 8.dp
    val space2 = 16.dp
    val space3 = 24.dp
    val space4 = 32.dp
    val pageInset = 20.dp
    val fontFamily = FontFamily(
        Font(R.font.ibm_plex_mono_regular, FontWeight.Normal),
        Font(R.font.ibm_plex_mono_medium, FontWeight.Medium),
        Font(R.font.ibm_plex_mono_semibold, FontWeight.SemiBold),
    )
    fun text(size: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(
        fontFamily = fontFamily,
        fontSize = size.sp,
        fontWeight = weight,
        color = ink,
    )
}

@Composable
fun ScreenChrome(
    title: String,
    subtitle: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = T9Theme.pageInset),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(title, style = T9Theme.text(26, FontWeight.Bold))
            if (subtitle != null) {
                Spacer(Modifier.height(8.dp))
                Text(subtitle, style = T9Theme.text(14).copy(color = T9Theme.muted))
            }
            Spacer(Modifier.height(T9Theme.space2))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(T9Theme.rule)
                    .background(T9Theme.hair.copy(alpha = 0.35f)),
            )
        }
        Spacer(Modifier.height(T9Theme.space3))
        content()
    }
}

@Composable
fun FieldLabel(text: String) {
    Text(
        text.uppercase(),
        style = T9Theme.text(11, FontWeight.SemiBold).copy(
            color = T9Theme.muted,
            letterSpacing = 1.2.sp,
        ),
    )
}

/** Hide the soft keyboard and clear text-field focus. */
@Composable
fun rememberKeyboardDismiss(): () -> Unit {
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    return remember(focusManager, keyboard) {
        {
            focusManager.clearFocus(force = true)
            keyboard?.hide()
        }
    }
}

/**
 * Form-screen keyboard UX: lift content above the IME and dismiss when the
 * user starts scrolling (or taps Done on single-line fields).
 */
fun Modifier.t9KeyboardDismiss(): Modifier = composed {
    val dismiss = rememberKeyboardDismiss()
    val connection = remember(dismiss) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available != Offset.Zero) {
                    dismiss()
                }
                return Offset.Zero
            }
        }
    }
    this
        .imePadding()
        .nestedScroll(connection)
}

@Composable
fun T9TextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    singleLine: Boolean = true,
    enabled: Boolean = true,
    minHeight: Dp = 48.dp,
) {
    val dismiss = rememberKeyboardDismiss()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(minHeight)
            .background(T9Theme.surface)
            .border(T9Theme.stroke, T9Theme.hair.copy(alpha = 0.55f), RectangleShape)
            .padding(horizontal = 14.dp, vertical = 14.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (value.isEmpty() && placeholder.isNotEmpty()) {
            Text(placeholder, style = T9Theme.text(15, FontWeight.Medium).copy(color = T9Theme.muted))
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = singleLine,
            textStyle = T9Theme.text(15, FontWeight.Medium),
            cursorBrush = SolidColor(T9Theme.accent),
            keyboardOptions = KeyboardOptions(
                imeAction = if (singleLine) ImeAction.Done else ImeAction.Default,
            ),
            keyboardActions = KeyboardActions(
                onDone = { dismiss() },
            ),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
fun PrimaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = T9Theme.ink,
    busy: Boolean = false,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled && !busy,
        modifier = modifier
            .fillMaxWidth()
            .height(48.dp)
            .background(tint),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = T9Theme.text(15, FontWeight.SemiBold).copy(color = Color.White))
            if (busy) {
                CircularProgressIndicator(
                    color = Color.White,
                    strokeWidth = 2.dp,
                    modifier = Modifier.height(18.dp).width(18.dp),
                )
            } else {
                Text("→", style = T9Theme.text(15, FontWeight.SemiBold).copy(color = Color.White))
            }
        }
    }
}

@Composable
fun SecondaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled && !busy,
        modifier = modifier
            .fillMaxWidth()
            .height(48.dp)
            .background(T9Theme.surface)
            .border(T9Theme.stroke, T9Theme.hair.copy(alpha = 0.55f), RectangleShape),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = T9Theme.text(15, FontWeight.Medium))
            if (busy) {
                CircularProgressIndicator(
                    color = T9Theme.ink,
                    strokeWidth = 2.dp,
                    modifier = Modifier.height(18.dp).width(18.dp),
                )
            }
        }
    }
}

@Composable
fun GhostButton(title: String, onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Text(title, style = T9Theme.text(14, FontWeight.Medium).copy(color = T9Theme.muted))
    }
}

@Composable
fun SurfacePanel(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(T9Theme.surface)
            .border(T9Theme.stroke, T9Theme.hair.copy(alpha = 0.45f), RectangleShape)
            .padding(T9Theme.space2),
        content = content,
    )
}

@Composable
fun StatusBadge(text: String, tone: Color = T9Theme.teal) {
    Text(
        text.uppercase(),
        style = T9Theme.text(10, FontWeight.SemiBold).copy(
            color = tone,
            letterSpacing = 1.2.sp,
        ),
        modifier = Modifier
            .background(tone.copy(alpha = 0.1f))
            .padding(horizontal = 8.dp, vertical = 5.dp),
    )
}

@Composable
fun EmptyStateBlock(title: String, detail: String? = null) {
    Column(modifier = Modifier.padding(vertical = T9Theme.space4)) {
        Text(title, style = T9Theme.text(16, FontWeight.SemiBold))
        if (detail != null) {
            Spacer(Modifier.height(8.dp))
            Text(detail, style = T9Theme.text(14).copy(color = T9Theme.muted))
        }
    }
}

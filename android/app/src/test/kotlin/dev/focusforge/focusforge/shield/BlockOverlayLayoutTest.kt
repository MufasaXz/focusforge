package dev.focusforge.focusforge.shield

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockOverlayLayoutTest {
    @Test fun sharedOverlayProvidesReadableActionsBeforeEitherEngineAttachesListeners() {
        val resources = File("src/main/res")
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val layout = factory.newDocumentBuilder().parse(File(resources, "layout/ff_block_overlay.xml"))
        val strings = factory.newDocumentBuilder().parse(File(resources, "values/strings.xml"))
        val names = strings.getElementsByTagName("string")
        val labels = (0 until names.length).associate {
            val node = names.item(it) as org.w3c.dom.Element
            node.getAttribute("name") to node.textContent
        }
        val buttons = layout.getElementsByTagName("Button")
        for (index in 0 until buttons.length) {
            val button = buttons.item(index) as org.w3c.dom.Element
            val text = button.getAttributeNS("http://schemas.android.com/apk/res/android", "text")
            val label = if (text.startsWith("@string/")) labels[text.removePrefix("@string/")] else text
            assertTrue("Action ${button.getAttributeNS("http://schemas.android.com/apk/res/android", "id")} needs a readable label",
                !label.isNullOrBlank())
        }
        assertTrue("The block must offer both actions", buttons.length == 2)
    }
}

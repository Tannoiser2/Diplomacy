extends SceneTree
## Scrive alcuni codici QR come immagini (tests/qr.sh li rilegge con un lettore vero).

func _init() -> void:
	var casi := ["https://tannoiser2.github.io/Diplomacy/?stanza=ABCD", "DIPLOMACY", "http://127.0.0.1:8099/index.html?stanza=WXYZ&prova=1",
		"Europa 1901: accordi, sotterfugi e tradimenti. Frase lunga per la versione cinque."]
	var cart := OS.get_environment("DP_QR_DIR")
	for i in casi.size():
		var t := DPQr.texture(casi[i], 8)
		t.get_image().save_png("%s/qr%d.png" % [cart, i])
		var f := FileAccess.open("%s/qr%d.txt" % [cart, i], FileAccess.WRITE)
		f.store_string(casi[i])
		f.close()
	quit(0)

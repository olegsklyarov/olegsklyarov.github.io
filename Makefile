.PHONY: format serve

MD_FILES := docs README.md

format:
	mdformat --extensions front_matters --extensions tables $(MD_FILES)

serve:
	mkdocs serve

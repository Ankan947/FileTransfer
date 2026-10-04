from PIL import Image

image_path = r"C:\Users\ankan\.gemini\antigravity\brain\4ae97a87-ceda-4f15-8565-6a299f0125e2\file_transfer_icon_2_1791055506152.jpg"
ico_path_1 = r"c:\Users\ankan\Downloads\GDR PROJECT\GDR PROJECT\GDR PROJECT\file_transfer_app\windows\runner\resources\app_icon.ico"
ico_path_2 = r"c:\Users\ankan\Downloads\GDR PROJECT\GDR PROJECT\GDR PROJECT\app_icon.ico"

img = Image.open(image_path)
# Resize to square
img = img.resize((256, 256), Image.Resampling.LANCZOS)
img.save(ico_path_1, format="ICO", sizes=[(256, 256), (128, 128), (64, 64), (32, 32), (16, 16)])
img.save(ico_path_2, format="ICO", sizes=[(256, 256), (128, 128), (64, 64), (32, 32), (16, 16)])

print("Icon saved!")

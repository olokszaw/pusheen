from django.contrib import admin
from django.conf import settings
from django.conf.urls.static import static
from django.urls import include, path
from watchparty.views import room_invite_page

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("watchparty.urls")),
    path("join/<str:invite_code>", room_invite_page),
]

if settings.DEBUG:
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)

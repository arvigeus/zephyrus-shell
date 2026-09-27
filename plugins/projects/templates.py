"""Project starters adapted from the Syntaxis server app.

Commands are fixed application data, run only after the user selects a starter.
They run in an interactive terminal inside the newly created project directory.
"""


def item(key, label, description, category, icon, command=None, requires=None):
    return dict(id=key, label=label, description=description, category=category,
                icon=icon, command=command, requires=requires)


TEMPLATES = [
    item("empty", "Empty", "Just a folder", "Basics", "folder"),
    item("rust", "Rust", "Cargo binary", "Basics", "rust",
         "mise x rust@stable -- cargo init . && mise use -y rust@stable"),
    item("python", "Python", "uv package", "Basics", "python",
         "mise x python@latest uv@latest -- uv init . && mise use -y python@latest uv@latest"),
    item("go", "Go", "Go module", "Basics", "go",
         'mise x go@latest -- sh -lc \'go mod init "$(basename "$PWD")"\' && mise use -y go@latest'),
    item("deno", "Deno", "Deno starter", "Basics", "denojs",
         "mise x deno@latest -- deno init . && mise use -y deno@latest"),
    item("bun", "Bun", "Interactive bun init", "Basics", "bun",
         "mise x bun@latest -- bun init && mise use -y bun@latest"),
    item("nodejs", "Node.js", "Interactive npm init", "Basics", "nodejs",
         "mise x node@lts -- npm init && mise use -y node@lts"),
    item("dotnet-console", ".NET Console", "C# console app", "Basics", "dotnetcore",
         "mise x dotnet@latest -- dotnet new console --output . && mise use -y dotnet@latest"),
    item("dioxus", "Dioxus", "Interactive 0.7 app", "Web", "rust",
         "mise x rust@stable cargo:dioxus-cli@0.7.10 -- dx new . --vcs none && mise use -y rust@stable cargo:dioxus-cli@0.7.10"),
    item("blazor", "Blazor", "Blazor Web App", "Web", "dotnetcore",
         "mise x dotnet@latest -- dotnet new blazor --output . && mise use -y dotnet@latest"),
    item("vite", "Vite", "Interactive framework picker", "Web", "vitejs",
         "mise x node@lts -- npx --yes create-vite@latest . && mise use -y node@lts"),
    item("vite-plus", "Vite+", "Unified toolchain picker", "Web", "vitejs",
         "vp create --directory .", requires="vp"),
    item("cloudflare", "Cloudflare", "Interactive Workers app", "Web", "cloudflare",
         "mise x node@lts -- npm create cloudflare@latest -- . && mise use -y node@lts"),
    item("shadcn", "shadcn/ui", "Interactive UI starter", "Web", "react",
         'mise x node@lts -- sh -lc \'project_name=$(basename "$PWD"); npx --yes shadcn@latest init --name "$project_name" && cp -a -- "$project_name"/. . && rm -rf -- "$project_name"\' && mise use -y node@lts'),
    item("react", "React", "Vite + TypeScript", "Web", "react",
         "mise x node@lts -- sh -lc 'npx --yes create-vite@latest . --template react-ts && npm install' && mise use -y node@lts"),
    item("vue", "Vue", "Interactive create-vue", "Web", "vuejs",
         "mise x node@lts -- npx --yes create-vue@latest . && mise use -y node@lts"),
    item("sveltekit", "SvelteKit", "Interactive sv create", "Web", "svelte",
         "mise x node@lts -- npx --yes sv@latest create . && mise use -y node@lts"),
    item("solidstart", "SolidStart", "Interactive Solid app", "Web", "solidjs",
         "mise x node@lts -- npx --yes create-solid@latest . && mise use -y node@lts"),
    item("nextjs", "Next.js", "Interactive create-next-app", "Web", "nextjs",
         "mise x node@lts -- npx --yes create-next-app@latest . && mise use -y node@lts"),
    item("astro", "Astro", "Interactive create-astro", "Web", "astro",
         "mise x node@lts -- npx --yes create-astro@latest . && mise use -y node@lts"),
    item("nuxt", "Nuxt", "Interactive create-nuxt", "Web", "nuxtjs",
         "mise x node@lts -- npx --yes create-nuxt@latest . && mise use -y node@lts"),
    item("tanstack-start", "TanStack Start", "Interactive add-on builder", "Web", "react",
         "mise x node@lts -- npx --yes @tanstack/cli@latest create . && mise use -y node@lts"),
    item("react-router", "React Router", "Framework mode starter", "Web", "reactrouter",
         "mise x node@lts -- npx --yes create-react-router@latest . && mise use -y node@lts"),
    item("hono", "Hono", "Interactive runtime picker", "Web", "hono",
         "mise x node@lts -- npx --yes create-hono@latest . && mise use -y node@lts"),
    item("fresh", "Fresh", "Interactive Deno app", "Web", "denojs",
         "mise x deno@latest -- deno run -Ar jsr:@fresh/init . && mise use -y deno@latest"),
    item("aspnet-api", "ASP.NET Core API", "Minimal Web API", "Backend", "dotnetcore",
         "mise x dotnet@latest -- dotnet new webapi --output . && mise use -y dotnet@latest"),
    item("aspire", ".NET Aspire", "Distributed app stack", "Backend", "dotnetcore",
         'mise x dotnet@latest aspire@latest -- sh -lc \'aspire new aspire-starter --name "$(basename "$PWD")" --output .\' && mise use -y dotnet@latest aspire@latest'),
    item("django", "Django", "uv + Django project", "Backend", "django",
         "mise x python@latest uv@latest -- sh -lc 'uv init --bare . && uv add django && uv run django-admin startproject config .' && mise use -y python@latest uv@latest"),
    item("expo", "React Native", "Interactive Expo app", "Native", "react",
         "mise x node@lts -- npx --yes create-expo-app@latest . && mise use -y node@lts"),
    item("tauri", "Tauri", "Interactive desktop app", "Native", "rust",
         "mise x node@lts rust@stable -- npx --yes create-tauri-app@latest . && mise use -y node@lts rust@stable"),
]

BY_ID = {template["id"]: template for template in TEMPLATES}

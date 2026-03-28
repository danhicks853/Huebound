import re, json

with open("achievements.vdf", "r", encoding="utf-8") as f:
    content = f.read()

achievements = []
blocks = re.findall(r'"(\d+)"\s*\{([^}]+)\}', content)
for block_id, block_body in blocks:
    fields = dict(re.findall(r'"(\w+)"\s+"([^"]*)"', block_body))
    if "name" in fields:
        achievements.append([
            fields["name"],
            fields.get("display_name", fields["name"]),
            fields.get("description", ""),
            1 if fields.get("hidden", "0") == "1" else 0
        ])

data_json = json.dumps(achievements, ensure_ascii=True)

js = "var D=" + data_json + ";"
js += "(async function(){"
js += 'var s=document.cookie.match(/sessionid=([^;]+)/);'
js += 'if(!s){console.error("No session");return;}s=s[1];'
js += "var ok=0,fail=0;"
js += "for(var i=0;i<D.length;i++){"
js += "var a=D[i];var f=new FormData();"
js += 'f.append("sessionid",s);'
js += 'f.append("appid","4459040");'
js += 'f.append("achievement_api_name",a[0]);'
js += 'f.append("achievement_display_name",a[1]);'
js += 'f.append("achievement_description",a[2]);'
js += 'f.append("achievement_hidden",String(a[3]));'
js += "try{"
js += 'var r=await fetch("https://partner.steamworks.com/apps/newachievement/4459040",{method:"POST",body:f,credentials:"include"});'
js += "if(r.ok){ok++;if(ok%25===0)console.log(ok+'/'+D.length);}"
js += 'else{fail++;if(fail<=3){var t=await r.text();console.warn("FAIL:"+a[0]+" "+r.status+" "+t.substring(0,100));}}'
js += '}catch(e){fail++;if(fail<=3)console.warn("ERR:"+a[0],e);}'
js += "await new Promise(function(r){setTimeout(r,200);});"
js += "}"
js += 'console.log("Done: "+ok+" ok, "+fail+" failed");'
js += "})();"

with open("create_achievements_min.js", "w", encoding="ascii") as f:
    f.write(js)

print("Generated create_achievements_min.js")
print(f"  {len(achievements)} achievements, {len(js)} chars, pure ASCII, single line")

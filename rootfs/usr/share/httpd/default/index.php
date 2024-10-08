<!DOCTYPE html>
<html lang="en">

<head>
  <!--
##@Version           :  202303091846-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  
# @@Copyright        :  Copyright: (c) 2023 Jason Hempstead, Casjays Developments
# @@Created          :  Thursday, Mar 09, 2023 18:46 EST
# @@File             :  index.php
# @@Description      :  php document
# @@Changelog        :  Updated header
# @@TODO             :  
# @@Other            :  
# @@Resource         :  
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  html
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
-->

  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />

  <meta content="text/html; charset=utf-8" http-equiv="Content-Type" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta name="robots" content="index, follow" />
  <meta name="generator" content="CasjaysDev" />

  <meta name="description" content="REPLACE_SERVER_SOFTWARE container" />
  <meta property="og:title" content="REPLACE_SERVER_SOFTWARE container" />
  <meta property="og:locale" content="en_US" />
  <meta property="og:type" content="website" />
  <meta property="og:image" content="./images/favicon.ico" />
  <meta property="og:url" content="" />

  <meta name="theme-color" content="#000000" />
  <link rel="manifest" href="./site.webmanifest" />

  <link rel="icon" type="image/icon png" href="./images/icon.png" />
  <link rel="apple-touch-icon" href="./images/icon.png" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.css" />
  <link rel="stylesheet" type="text/css" href="./css/cookieconsent.css" />
  <link rel="stylesheet" href="./css/bootstrap.css" />
  <link rel="stylesheet" href="./css/index.css" />
  <script src="./js/errorpages/isup.js"></script>
  <script src="./js/errorpages/homepage.js"></script>
  <script src="./js/errorpages/loaddomain.js"></script>
  <script src="./js/jquery/default.js"></script>
  <script src="./js/passprotect.min.js" defer></script>
  <script src="./js/bootstrap.min.js" defer></script>
  <script src="./js/app.js" defer></script>
</head>

<body class="container text-center" style="align-items: center; justify-content: center">
  <h1 class="m-5">Congratulations</h1>
  <h2>
    Your REPLACE_SERVER_SOFTWARE container has been setup.<br />
    This file is located in:
    <?php echo $_SERVER['DOCUMENT_ROOT']; ?><br />
    <br />
    SERVER:
    <?php echo $_SERVER['SERVER_SOFTWARE']; ?> <br />
    SERVER Address:
    <?php echo $_SERVER['SERVER_ADDR']; ?> <br />
  </h2>
  <br /><br />
  <br /><br />
  <br /><br />
  <!-- Begin EU compliant -->
  <div class="footer-custom" align="center">
    <div class="text-center align-items-center fs-3">
      <link rel="stylesheet" type="text/css" href="/css/cookieconsent.css" />
      <script src="/js/cookieconsent.js"></script>
      <script>
        window.addEventListener("load", function() {
          window.cookieconsent.initialise({
            "palette": {
              "popup": {
                "background": "#64386b",
                "text": "#ffcdfd"
              },
              "button": {
                "background": "transparent",
                "text": "#f8a8ff",
                "border": "#f8a8ff"
              }
            },
            "content": {
              "message": "In accordance with the EU GDPR law this message is being displayed. - ",
              "dismiss": "I Agree",
              "link": "CasjaysDev Policy",
              "href": "https://casjaysdev.pro/policy/"
            },
            "type": "opt-out"
          })
        });
      </script>
    </div>
  </div>
  <br />
  <!-- End EU compliant -->
</body>

</html>

## Running locally
rackup
## Running locally as a container
docker build -t osspublish .
docker run -e RACK_ENV=development -e PORT=18888 -p 18888:18888 -it osspublish
## Deploying to heroku
heroku stack:set container
git push heroku master

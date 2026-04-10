## Running locally

bundle install
bundle exec puma

## Running locally as a container

docker build -t osspublish .
docker run -e RACK_ENV=development -e PORT=18888 -p 18888:18888 -it osspublish

## Deploying to Fly

echo "PORT=8080\nRACK_ENV=production" | fly secrets import
fly launch

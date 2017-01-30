package com.mygdx.game;

import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.math.Vector2;

/**
 * Created by Денис on 22.01.2017.
 */
public class Background {

    class Stars {
        private Vector2 position;
        private float speedX;
        private float speedY;

        public  Stars (){
            position = new Vector2((float) Math.random() * 1280,(float) Math.random() * 720);
            speedX =  0.5f;
            speedY =  0.5f;
        }
        public void update (){
            position.x -= speedX;
           // position.y -=speedY;
            if (position.x < -20 || position.y < -20){
                position.x = 1280;
                position.y = (float) Math.random() * 720;
            }
        }
    }

    private Texture texture;
    private Texture textureStar;
    private Stars[] stars;
    private final int SATRS_count =200;
    public Background() {
        texture = new Texture("bg.png");
        textureStar = new Texture("zvezdets2.png");
        stars = new Stars[SATRS_count];
        for (int i = 0; i <SATRS_count ; i++) {
            stars [i] = new Stars();
        }
    }
    public void render (SpriteBatch batch) {
        batch.draw(texture,0,0);
        for (int i = 0; i <stars.length; i++) {
            batch.draw(textureStar,stars[i].position.x,stars[i].position.y);
        }
    }
    public void update (){
        for (int i = 0; i <stars.length ; i++) {
            stars[i].update();
        }
    }


}

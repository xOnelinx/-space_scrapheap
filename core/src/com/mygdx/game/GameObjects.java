package com.mygdx.game;

        import com.badlogic.gdx.Gdx;
        import com.badlogic.gdx.graphics.Texture;
        import com.badlogic.gdx.graphics.g2d.SpriteBatch;
        import com.badlogic.gdx.math.Rectangle;
        import com.badlogic.gdx.math.Vector2;


/**
 * Created by Денис on 22.01.2017.
 */
public class GameObjects {

    public class Asteroids{
        private Vector2 speed;
       private Vector2 position;
        private Rectangle rect;

        public Asteroids() {
            position = new Vector2((float) Math.random() * 1280,(float) Math.random() * 720);
            speed = new Vector2(((float) Math.random()-0.5f) ,((float) Math.random()-0.5f) );
           rect = new Rectangle(position.x,position.y,60,60);
        }
        public void update (){
            position.add(speed);
            if (position.x > 1320){ speed.scl(-1f);  }
            if (position.x < -60){ speed.scl(-1f);  }
            if (position.y > 860){ speed.scl(-1f);  }
            if (position.y < -60){ speed.scl(-1f);  }

            rect.x = position.x;    rect.y=position.y;
        }

    }

    private static Texture texture;
    private static Vector2 position;
    private  Asteroids[] asteroids;
    private  int OBJ_COUNTER =20;


    public GameObjects() {
        texture =  new Texture("asteroid60.tga");
        position = new Vector2((float)Math.random()*1280,(float)Math.random()*720);

        asteroids = new Asteroids[OBJ_COUNTER];
        for (int i = 0; i <asteroids.length ; i++) {
            asteroids[i]= new Asteroids();
        }
    }



    public void render(SpriteBatch batch){
        batch.draw(texture,Gdx.graphics.getWidth()/2,Gdx.graphics.getHeight()/2);
        for (int i = 0; i <asteroids.length ; i++) {
            batch.draw(texture,asteroids[i].position.x,asteroids[i].position.y);
        }
    }
    public void update(){
        for (int i = 0; i <asteroids.length ; i++) {
           asteroids[i].update();
        }

    }
}

package com.mygdx.game;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Input;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.math.Vector2;

/**
 * Created by Денис on 22.01.2017.
 */
public class Hero {
    private Texture texture;
    private Vector2 position;
    private Vector2 speed;

    private float angle;

    public Vector2 getPosition() {
        return position;
    }

    public Vector2 getSpeed() {
        return speed;
    }

    public float getAngle() {
        return angle;
    }

    public Hero() {
        texture = new Texture("cosmoman2.png");
        position = new Vector2(100,100);
        speed = new Vector2(0.1f,0.1f);
        angle = 0;
    }
    public void render(SpriteBatch batch){
        batch.draw(texture,position.x,position.y,32,32,64,64,0.5f,0.5f,angle,0,0,64,64,false,false);
    }

    public void update (){
      /* if (Gdx.input.isKeyPressed(Input.Keys.UP)){        position.y += speed.y;        }
        if (Gdx.input.isKeyPressed(Input.Keys.DOWN)){        position.y -= speed.y;        }
        if (Gdx.input.isKeyPressed(Input.Keys.RIGHT)){        position.x += speed.x;        }
        if (Gdx.input.isKeyPressed(Input.Keys.LEFT)){        position.x -= speed.x;        }*/

        position.add(speed);
        if (position.y > 656) position.y = 656;
        if (position.y < 0) position.y = 0;
        if (position.x > 1216) position.x=1216;
        if (position.x < 0) position.x=0;

      if (InputHander.isPressed()) {
           speed = position.cpy().sub(InputHander.getMousePoz()).nor().scl(-1f);

       }

    }

}
